@testset "Joint density reduction: overlap, faces, actors and time" begin
    unit = ones(1,1,1)
    overlap = ones(1,1,1,2)
    @test joint_srppa(overlap, unit, unit) ≈ sqrt(2)
    @test joint_srppa(overlap, unit, unit) != 2.0
    @test joint_srppa(overlap, unit, unit) != 1.0
    @test joint_srppa(overlap, 3unit, 2unit) ≈ 6sqrt(2)
    disjoint = zeros(1,1,2,2)
    disjoint[1,1,1,1] = disjoint[1,1,2,2] = 1
    @test joint_srppa(disjoint, ones(1,1,2), ones(1,1,2)) == 2.0
    actors = zeros(1,2,1,2)
    actors[1,1,1,1] = actors[1,2,1,2] = 1
    @test joint_srppa(actors, reshape([1.0,3.0],1,2,1), ones(1,2,1)) == 4.0
    @test joint_srppa(ones(2,1,1,2), ones(2,1,1), ones(2,1,1)) ≈ 2sqrt(2)
    @test joint_srppa(zeros(1,1,1,0), unit, unit) == 0.0
    @test joint_srppa(overlap, zero(unit), unit) == 0.0
    @test_throws ArgumentError joint_srppa(-overlap, unit, unit)
    @test_throws ArgumentError joint_srppa(fill(NaN,1,1,1,1), unit, unit)
    @test_throws ArgumentError joint_srppa(fill(Inf,1,1,1,1), unit, unit)
    @test_throws ArgumentError joint_srppa(overlap, -unit, unit)
    @test_throws ArgumentError joint_srppa(overlap, unit, -unit)
    @test_throws DimensionMismatch joint_srppa(overlap, ones(2,1,1), unit)
end

@testset "Model-based SRPPA validation, weighting and order" begin
    configs = smoke_configuration(load_scenario())
    state = first(initial_states(configs))
    path = [M.MDPState(state.state,t,configs.horizon) for t in 1:configs.horizon]
    selections = [(1,path), (2,copy(path))]
    single = joint_srppa(configs, selections[1:1])
    @test single > 0
    @test joint_srppa(configs, selections) ≈ sqrt(2) * single
    @test joint_srppa(configs, selections) === joint_srppa(configs, reverse(selections))
    @test marginal_srppa(configs, selections[1:1], selections[2]) ≈ (sqrt(2)-1) * single
    @test marginal_srppa(configs, [], selections[1]) ≈ single
    @test joint_srppa(configs, []) == 0.0
    @test motion_bonuses(configs, []) == (heading_bonus=0.0, stationary_bonus=0.0)
    bonuses = motion_bonuses(configs, selections)
    @test bonuses == (heading_bonus=0.12, stationary_bonus=0.06)
    mixed_path = [M.MDPState(M.UAVState(10,10,:N),1,4),
                  M.MDPState(M.UAVState(11,10,:N),2,4),
                  M.MDPState(M.UAVState(11,10,:E),3,4),
                  M.MDPState(M.UAVState(11,10,:E),4,4)]
    @test motion_bonuses(configs, [(1,mixed_path)]) == (heading_bonus=0.04, stationary_bonus=0.02)
    empty_solution = S.Solution(17.0, Tuple{Int,Vector{M.MDPState}}[])
    @test evaluate_solution(configs, empty_solution) ==
        (joint_srppa=0.0, legacy_value=17.0, heading_bonus=0.0, stationary_bonus=0.0)
    weighted = deepcopy(configs)
    for target in weighted.target_trajectories, face in target.faces
        face.weight *= 3
    end
    @test joint_srppa(weighted, selections) ≈ 3joint_srppa(configs, selections)
    @test_throws ArgumentError joint_srppa(configs, [selections[1],selections[1]])
    @test_throws ArgumentError marginal_srppa(configs, selections[1:1], selections[1])
    @test_throws ArgumentError joint_srppa(configs, [(0,path)])
    @test_throws ArgumentError joint_srppa(configs, [(3,path)])
    @test_throws ArgumentError joint_srppa(configs, [(1,path[1:3])])
    @test_throws ArgumentError joint_srppa(configs, [(1,reverse(path))])
    wrong_depth = copy(path); wrong_depth[2] = M.MDPState(state.state,1,configs.horizon)
    @test_throws ArgumentError joint_srppa(configs, [(1,wrong_depth)])
    wrong_horizon = copy(path); wrong_horizon[1] = M.MDPState(state.state,1,999)
    @test_throws ArgumentError joint_srppa(configs, [(1,wrong_horizon)])
    for position in (NaN, Inf)
        bad = copy(path); bad[1] = M.MDPState(M.UAVState(position,1.0,:N),1,configs.horizon)
        @test_throws ArgumentError joint_srppa(configs, [(1,bad)])
    end
    @test_throws ArgumentError joint_srppa(configs, [(1,fill(:invalid,configs.horizon))])
    @test_throws ArgumentError joint_srppa(configs, [path])
    @test_throws ArgumentError joint_srppa(configs, nothing)
    bad_weights = deepcopy(configs); bad_weights.target_trajectories[1,1].faces[1].weight = -1
    @test_throws ArgumentError joint_srppa(bad_weights, selections)
    bad_shape = deepcopy(configs); bad_shape.horizon += 1
    @test_throws ArgumentError joint_srppa(bad_shape, selections)
    # Pinhole and view-cone use the configured sensor; scoring never substitutes one.
    pinhole = deepcopy(configs)
    pinhole.sensor = M.PinholeCameraModel([20.0,20.0], [3840.0,2160.0], [35.0,24.0], 0.0, -0.3490655, 100.0)
    @test isfinite(joint_srppa(pinhole, selections))
end

function check_joint_evaluation(solution, configs; check_transitions=true)
    original_value = solution.value
    scores = evaluate_solution(configs, solution)
    @test isfinite(scores.joint_srppa) && scores.joint_srppa >= 0
    @test scores.legacy_value == legacy_value(solution) == original_value
    @test solution.value == original_value
    reversed = S.Solution(solution.value, reverse(solution.elements))
    @test evaluate_solution(configs, reversed) == scores
    for candidate in solution.elements
        prior = filter(e -> first(e) != first(candidate), solution.elements)
        gain = marginal_srppa(configs, prior, candidate)
        @test gain ≈ scores.joint_srppa - joint_srppa(configs, prior) atol=1e-11 rtol=1e-12
        # Independent comparison against the unchanged single-robot marginal reward.
        coverage = M.compute_prior_coverage(configs, M.Trajectory[last(e) for e in prior])
        path = last(candidate)
        model = M.SingleRobotMultiTargetViewCoverageProblem(configs.grid, configs.sensor,
            configs.horizon, configs.target_trajectories, Int(configs.move_dist), coverage, first(path))
        full_path_marginal = sum(M.compute_single_agent_view_reward(model,s) for s in path)
        @test gain ≈ full_path_marginal atol=1e-11 rtol=1e-12
        if check_transitions
            bonuses = motion_bonuses(configs, [candidate])
            transition_reward = sum(POMDPs.reward(model,path[t-1],path[t]) for t in 2:length(path))
            initial_view = M.compute_single_agent_view_reward(model,first(path))
            @test gain ≈ transition_reward - bonuses.heading_bonus - bonuses.stationary_bonus + initial_view atol=1e-11 rtol=1e-12
        end
    end
    # Log fresh numerical evidence during Pkg.test; no precomputed solutions are read.
    println("FRESH_SRPPA ", scores)
end
