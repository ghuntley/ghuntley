name: Gitignore Disk Images
description: Automatically ignore disk image files in git
tags: [git, ignore, disk-images]
files: [".gitignore"]
on_file_create: true

# Gitignore Disk Images

When .gitignore is created or modified, ensure these patterns are present:

1. Add patterns:
```gitignore
# Disk images
*.iso
*.qcow2
```

This will:
1. Ignore all ISO disk images
2. Ignore all QCOW2 virtual disk images
3. Apply recursively to all subdirectories

Note: These files should be distributed through other means (like binary caches) rather than version control.
