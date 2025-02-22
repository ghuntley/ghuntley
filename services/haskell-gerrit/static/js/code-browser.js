/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Code Browser functionality
$(document).ready(function () {
    // Syntax highlighting
    hljs.highlightAll();

    // File tree navigation
    $('.file-tree').on('click', '.directory', function (e) {
        e.preventDefault();
        $(this).toggleClass('expanded');
        $(this).next('.subtree').slideToggle();
    });

    // File content modal
    $('.file-link').click(function (e) {
        e.preventDefault();
        const path = $(this).data('path');
        const ref = $(this).data('ref');

        $.get(`/api/projects/${projectName}/files/${ref}/${path}`, function (response) {
            $('#fileModal')
                .find('.modal-title').text(path).end()
                .find('code').text(response.content).end()
                .modal('show');
            hljs.highlightElement($('#fileModal code')[0]);
        });
    });

    // File history
    function loadFileHistory(path, ref) {
        $.get(`/api/projects/${projectName}/files/${ref}/${path}/history`, function (commits) {
            const list = $('<div class="list-group">');
            commits.forEach(commit => {
                list.append(`
                    <div class="list-group-item">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="mb-1">${commit.subject}</h6>
                                <small class="text-muted">
                                    ${commit.author} - ${new Date(commit.date).toLocaleString()}
                                </small>
                            </div>
                            <div class="btn-group btn-group-sm">
                                <a href="/projects/${projectName}/files/${commit.hash}/${path}"
                                   class="btn btn-outline-secondary">
                                    View
                                </a>
                                <button class="btn btn-outline-secondary"
                                        onclick="diffWithPrevious('${path}', '${commit.hash}')">
                                    Diff
                                </button>
                            </div>
                        </div>
                    </div>
                `);
            });
            $('#historyModal').find('.modal-body').empty().append(list).end().modal('show');
        });
    }

    // Diff viewer
    function diffWithPrevious(path, commit) {
        $.get(`/api/projects/${projectName}/files/${commit}/${path}/diff`, function (diff) {
            $('#diffModal')
                .find('.modal-title').text(`Changes to ${path}`).end()
                .find('.modal-body').html(diff).end()
                .modal('show');
        });
    }

    // Search in files
    let searchTimeout;
    $('#fileSearch').on('input', function () {
        clearTimeout(searchTimeout);
        const query = $(this).val();
        if (query.length < 2) return;

        searchTimeout = setTimeout(() => {
            $.get(`/api/projects/${projectName}/search`, { q: query }, function (results) {
                const list = $('#searchResults').empty();
                results.forEach(result => {
                    list.append(`
                        <div class="list-group-item">
                            <h6 class="mb-1">
                                <a href="/projects/${projectName}/files/${currentRef}/${result.path}">
                                    ${result.path}
                                </a>
                            </h6>
                            <pre class="small mb-0"><code>${result.preview}</code></pre>
                        </div>
                    `);
                });
            });
        }, 300);
    });

    // Keyboard shortcuts
    $(document).keydown(function (e) {
        if (e.ctrlKey || e.metaKey) {
            switch (e.key) {
                case 'f':
                    e.preventDefault();
                    $('#fileSearch').focus();
                    break;
                case 'b':
                    e.preventDefault();
                    window.location.href = `/projects/${projectName}/browse`;
                    break;
            }
        }
    });
});
