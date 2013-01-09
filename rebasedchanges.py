import sys
import os

args = sys.argv[1:]
delimiter = args.index('-')

changes = args[0:delimiter]
repos = args[delimiter + 1:]

i = 0

for change in changes:
    project = repos[i]
    
    print change + " in " + project
    project = project.replace('CyanogenMod/', '')

    path = project.replace('android_', '')
    path = path.replace('_', '/')

    os.system('cd %s ; git fetch git://github.com/finnq/%s.git ; git cherry-pick %s' % (path, project, change))

    i = i + 1
