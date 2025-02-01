/*
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

#ifndef UI_LOG_H
#define UI_LOG_H

extern void cgit_print_log(const char *tip, int ofs, int cnt, char *grep,
			   char *pattern, const char *path, int pager,
			   int commit_graph, int commit_sort);
extern void show_commit_decorations(struct commit *commit);

#endif /* UI_LOG_H */
