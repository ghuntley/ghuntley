% Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
% SPDX-License-Identifier: Proprietary

-module(hello).
-export([hello_world/0]).

hello_world() -> io:fwrite("hello, world\n").
