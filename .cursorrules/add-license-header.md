name: Add License Header
description: Automatically add license headers to new files using depot-addlicense
tags: [license, automation]
files: ["*"]
on_file_create: true

# Add License Header

When a new file is created:

1. Execute command:
```bash
depot-addlicense "$FILE"
```

This will:
1. Add the appropriate license header based on file type
2. Preserve any existing content
3. Follow depot's licensing conventions

Example headers:

For Go files:
```go
// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary
```

For Nix files:
```nix
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
```

For Shell scripts:
```bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary
```

Note: The depot-addlicense tool must be available in your PATH for this rule to work.
