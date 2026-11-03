"""Read-only Blender camera metadata; no rendering or saves, auto-exec must be disabled."""
import bpy,json,pathlib,argparse,sys
parser=argparse.ArgumentParser();parser.add_argument('--source-root',type=pathlib.Path,required=True);parser.add_argument('--output',type=pathlib.Path,required=True)
a=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
rows=[]
for n in ['cluster','cross_mix','four_split','priority_runners','priority_speaker','split_and_join','spreadout_group','track_runners']:
    bpy.ops.wm.open_mainfile(filepath=str(a.source_root/'experiments'/n/f'{n}.blend'),load_ui=False,use_scripts=False)
    rows.append(dict(scenario=n,camera_data=[dict(name=c.name,users=c.users,angle=c.angle) for c in bpy.data.cameras],camera_objects=[dict(name=o.name,data=o.data.name) for o in bpy.data.objects if o.type=='CAMERA'],active_camera=bpy.context.scene.camera.name if bpy.context.scene.camera else None))
a.output.write_text(json.dumps(rows,indent=2)+'\n');print('CAMERA_INSPECTION_OK')
