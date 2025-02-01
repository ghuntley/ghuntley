/*
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

extern void scan_projects(const char *path, const char *projectsfile, repo_config_fn fn);
extern void scan_tree(const char *path, repo_config_fn fn);
