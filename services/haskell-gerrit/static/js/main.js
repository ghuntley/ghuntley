/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Project List Search and Sort
$(document).ready(function () {
    // Project search functionality
    $('#projectSearch').on('input', function () {
        const searchTerm = $(this).val().toLowerCase();
        $('.project-item').each(function () {
            const name = $(this).data('name').toLowerCase();
            const desc = $(this).find('.text-muted').text().toLowerCase();
            $(this).toggle(name.includes(searchTerm) || desc.includes(searchTerm));
        });
    });

    // Project sorting
    $('.dropdown-item[data-sort]').click(function (e) {
        e.preventDefault();
        const sortBy = $(this).data('sort');
        const items = $('.project-item').get();

        items.sort(function (a, b) {
            const aVal = $(a).data(sortBy);
            const bVal = $(b).data(sortBy);
            return aVal > bVal ? 1 : -1;
        });

        $('#projectList').append(items);
    });
});

// Diff view enhancements
$(document).ready(function () {
    // Line highlighting
    $('.diff-line').hover(
        function () {
            $(this).addClass('highlight');
        },
        function () {
            $(this).removeClass('highlight');
        }
    );

    // Comment placement
    $('.comment-marker').each(function () {
        const file = $(this).data('file');
        const line = $(this).data('line');
        const target = $(`.diff-line[data-file="${file}"][data-line="${line}"]`);
        if (target.length) {
            $(this).insertAfter(target);
        }
    });

    // Syntax highlighting
    if (typeof hljs !== 'undefined') {
        $('pre code').each(function (i, block) {
            hljs.highlightBlock(block);
        });
    }
});

// Change review enhancements
$(document).ready(function () {
    // Vote selection highlighting
    $('#vote').change(function () {
        const value = $(this).val();
        $(this).removeClass('text-success text-danger text-warning')
            .addClass(getVoteClass(value));
    });

    // Comment preview
    let previewTimeout;
    $('#comment').on('input', function () {
        clearTimeout(previewTimeout);
        previewTimeout = setTimeout(() => {
            const text = $(this).val();
            if (text) {
                $.post('@{PreviewR}', { text: text }, function (html) {
                    $('#commentPreview').html(html);
                });
            }
        }, 500);
    });

    // File tree navigation
    $('.file-tree').on('click', '.directory', function (e) {
        e.preventDefault();
        $(this).toggleClass('expanded')
            .next('.files').slideToggle(200);
    });
});

// User profile enhancements
$(document).ready(function () {
    // Activity timeline animation
    $('.timeline-item').each(function (i) {
        $(this).css({
            'animation': `fadeInUp 0.3s ease forwards ${i * 0.1}s`,
            'opacity': 0
        });
    });

    // Statistics counter animation
    $('.statistics h3').each(function () {
        const $counter = $(this);
        const finalValue = parseInt($counter.text());
        $({ count: 0 }).animate({ count: finalValue }, {
            duration: 1000,
            step: function () {
                $counter.text(Math.floor(this.count));
            },
            complete: function () {
                $counter.text(finalValue);
            }
        });
    });
});

// Utility functions
function getVoteClass(vote) {
    switch (vote) {
        case 'PlusTwo': return 'text-success';
        case 'PlusOne': return 'text-success';
        case 'Zero': return '';
        case 'MinusOne': return 'text-warning';
        case 'MinusTwo': return 'text-danger';
        default: return '';
    }
}

// Toast notifications
const Toast = {
    show: function (message, type = 'info') {
        const toast = $(`
            <div class="toast" role="alert">
                <div class="toast-header">
                    <strong class="mr-auto">${type.charAt(0).toUpperCase() + type.slice(1)}</strong>
                    <button type="button" class="ml-2 mb-1 close" data-dismiss="toast">
                        <span>&times;</span>
                    </button>
                </div>
                <div class="toast-body">${message}</div>
            </div>
        `);

        $('.toast-container').append(toast);
        toast.toast({ delay: 3000 }).toast('show');
    }
};

// Keyboard shortcuts
$(document).keydown(function (e) {
    if (e.ctrlKey || e.metaKey) {
        switch (e.key) {
            case '/':
                e.preventDefault();
                $('#projectSearch').focus();
                break;
            case 'Enter':
                if ($('#comment').is(':focus')) {
                    e.preventDefault();
                    $('#commentForm').submit();
                }
                break;
        }
    }
});
