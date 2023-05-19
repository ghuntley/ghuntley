/**
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

import { hello } from './hello-world'

describe('Hello World', () => {
  it('says hello world', () => {
    expect(hello()).toEqual('Hello, World!')
  })
})
