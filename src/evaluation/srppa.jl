# Joint analytical SRPPA. Camera geometry and planner reward code remain upstream.

_elements(solution::SubmodularMaximization.Solution) = solution.elements
_elements(elements::AbstractVector) = elements
_elements(_) = throw(ArgumentError("expected a Solution or vector of (robot_id, trajectory) tuples"))

function _nonnegative_finite(values, name)
    all(x -> isfinite(x) && x >= 0, values) ||
        throw(ArgumentError("$name must contain finite nonnegative values"))
end

function _face_parameters(configs)
    configs.horizon > 0 || throw(ArgumentError("horizon must be positive"))
    configs.num_robots >= 0 || throw(ArgumentError("team size must be nonnegative"))
    size(configs.target_trajectories, 1) == configs.horizon ||
        throw(ArgumentError("target trajectories must span the configured horizon"))
    configs.grid.horizon == configs.horizon || throw(ArgumentError("grid horizon mismatch"))
    max_faces = maximum((length(t.faces) for t in configs.target_trajectories); init=0)
    shape = (configs.horizon, size(configs.target_trajectories, 2), max_faces)
    weights, areas = zeros(shape), zeros(shape)
    for t in 1:configs.horizon, a in axes(configs.target_trajectories, 2)
        target = configs.target_trajectories[t, a]
        all(isfinite, (target.x, target.y, target.heading)) ||
            throw(ArgumentError("actor poses must be finite"))
        for (f, face) in enumerate(target.faces)
            length(face.pos) == 2 && length(face.normal) == 3 ||
                throw(ArgumentError("invalid face geometry dimensions"))
            all(isfinite, face.pos) && all(isfinite, face.normal) ||
                throw(ArgumentError("face geometry must be finite"))
            weights[t,a,f], areas[t,a,f] = face.weight, face.size
        end
    end
    _nonnegative_finite(weights, "face weights")
    _nonnegative_finite(areas, "face areas")
    weights, areas
end

# Structural validation applies to every baseline, including the original continuous,
# unconstrained formation reference. Movement feasibility is a separate property.
function _canonical_elements(configs, selections)
    entries = Tuple{Int,Vector{MDMA.MDPState}}[]
    seen = Set{Int}()
    for entry in _elements(selections)
        entry isa Tuple && length(entry) == 2 ||
            throw(ArgumentError("each selection must be (robot_id, trajectory)"))
        robot, path = entry
        robot isa Integer && 1 <= robot <= configs.num_robots ||
            throw(ArgumentError("robot ID must lie in 1:num_robots"))
        robot in seen && throw(ArgumentError("duplicate robot ID: $robot"))
        push!(seen, robot)
        path isa AbstractVector && length(path) == configs.horizon ||
            throw(ArgumentError("each trajectory must span the configured horizon"))
        for (t, state) in enumerate(path)
            state isa MDMA.MDPState || throw(ArgumentError("trajectory states must be MDPState values"))
            state.depth == t || throw(ArgumentError("trajectory depths must be 1:horizon in order"))
            state.horizon == configs.horizon || throw(ArgumentError("state horizon mismatch"))
            all(isfinite, (state.state.x, state.state.y)) ||
                throw(ArgumentError("robot positions must be finite"))
            state.state.heading in MDMA.cardinaldir || throw(ArgumentError("invalid robot heading"))
        end
        push!(entries, (Int(robot), MDMA.MDPState[s for s in path]))
    end
    # Canonical accumulation order gives repeatable results even when callers reorder robots.
    sort!(entries; by=first)
end

function _add_density!(density, configs, path)
    for (t, state) in enumerate(path)
        theta = MDMA.dirAngle(state.state.heading)
        heading = (cos(theta), sin(theta), 0.0)
        for a in axes(configs.target_trajectories, 2)
            target = configs.target_trajectories[t,a]
            if MDMA.detectTarget(state.state, target, configs.sensor)
                for (f, face) in enumerate(target.faces)
                    distance = (face.pos[1] - state.state.x,
                                face.pos[2] - state.state.y,
                                MDMA.target_height / 2 - MDMA.drone_height)
                    contribution = MDMA.compute_camera_coverage(face, heading, distance)
                    isfinite(contribution) && contribution >= 0 ||
                        throw(ArgumentError("camera density must be finite and nonnegative"))
                    density[t,a,f] += contribution
                end
            end
        end
    end
    density
end

function _density(configs, entries, shape)
    density = zeros(shape)
    for (_, path) in entries
        _add_density!(density, configs, path)
    end
    density
end

# The single reduction used by both model-based and numerical-fixture evaluation.
function _quality(density, weights, areas)
    size(density) == size(weights) == size(areas) || throw(DimensionMismatch("face array shapes must agree"))
    _nonnegative_finite(density, "camera densities")
    _nonnegative_finite(weights, "face weights")
    _nonnegative_finite(areas, "face areas")
    total = 0.0
    for i in CartesianIndices(density)
        total += weights[i] * areas[i] * sqrt(density[i])
    end
    isfinite(total) || throw(ArgumentError("SRPPA overflowed"))
    total
end

"""
    joint_srppa(configs, selections_or_solution)

Authoritative analytical objective: sum over time, actors and faces of
`weight * area * sqrt(sum(robot_camera_densities))`. Uses the configured, unchanged
camera model. Accepts partial/empty selections; rejects duplicate IDs and malformed
trajectories. Does not include motion bonuses or assert movement feasibility.
"""
function joint_srppa(configs::MDMA.MultiDroneMultiActorConfigs, selections)
    weights, areas = _face_parameters(configs)
    entries = _canonical_elements(configs, selections)
    _quality(_density(configs, entries, size(weights)), weights, areas)
end

"""
    joint_srppa(contributions, weights, areas)

Numerical entry point for known densities. `contributions` has dimensions
(time, actor, face, robot); weights and areas have dimensions (time, actor, face).
Uses the same reduction as model-based evaluation. Empty robot axes yield zero.
"""
function joint_srppa(contributions::AbstractArray{<:Real,4},
                     weights::AbstractArray{<:Real,3}, areas::AbstractArray{<:Real,3})
    size(contributions)[1:3] == size(weights) == size(areas) ||
        throw(DimensionMismatch("face array shapes must agree"))
    _nonnegative_finite(contributions, "camera contributions")
    density = zeros(size(weights))
    for r in axes(contributions, 4), i in CartesianIndices(density)
        density[i] += contributions[i,r]
    end
    _quality(density, weights, areas)
end

"""
    marginal_srppa(configs, prior, candidate)

Pure SRPPA gain of adding one `(robot_id, trajectory)` to a prior selection.
Computes per-face increments independently of subtracting two total scores.
The candidate must have an ID absent from the prior selection.
"""
function marginal_srppa(configs::MDMA.MultiDroneMultiActorConfigs, prior, candidate::Tuple)
    weights, areas = _face_parameters(configs)
    entries = _canonical_elements(configs, prior)
    combined = _canonical_elements(configs, [entries; [candidate]])
    addition = only(filter(e -> first(e) == first(candidate), combined))
    before = _density(configs, entries, size(weights))
    extra = _density(configs, [addition], size(weights))
    _nonnegative_finite(before, "prior densities")
    _nonnegative_finite(extra, "additional densities")
    gain = 0.0
    for i in CartesianIndices(before)
        gain += weights[i] * areas[i] * (sqrt(before[i] + extra[i]) - sqrt(before[i]))
    end
    isfinite(gain) || throw(ArgumentError("marginal SRPPA overflowed"))
    gain
end

"""Report original 0.02/0.01 bonuses on actual adjacent transitions, excluding a fictitious initial self-transition."""
function motion_bonuses(configs::MDMA.MultiDroneMultiActorConfigs, selections)
    entries = _canonical_elements(configs, selections)
    heading_count = stationary_count = 0
    for (_, path) in entries, t in 2:length(path)
        previous, current = path[t-1].state, path[t].state
        heading_count += previous.heading == current.heading
        stationary_count += previous.x == current.x && previous.y == current.y
    end
    (heading_bonus=0.02 * heading_count, stationary_bonus=0.01 * stationary_count)
end

"""The unchanged stored upstream objective (or formation placeholder); never interpreted as joint SRPPA."""
legacy_value(solution::SubmodularMaximization.Solution) = solution.value

"""Evaluate any baseline with common joint SRPPA, keeping its stored legacy value and transition bonuses separate."""
function evaluate_solution(configs::MDMA.MultiDroneMultiActorConfigs, solution::SubmodularMaximization.Solution)
    quality = joint_srppa(configs, solution)
    bonuses = motion_bonuses(configs, solution)
    (joint_srppa=quality, legacy_value=legacy_value(solution),
     heading_bonus=bonuses.heading_bonus, stationary_bonus=bonuses.stationary_bonus)
end
