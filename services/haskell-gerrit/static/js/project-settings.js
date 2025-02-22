/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Branch Management
function editBranch(branchName) {
    $.get(`/api/projects/${projectName}/branches/${branchName}`, function (branch) {
        $('#editBranchModal')
            .find('[name="name"]').val(branch.name).end()
            .find('[name="protected"]').prop('checked', branch.protected).end()
            .modal('show');
    });
}

function deleteBranch(branchName) {
    if (confirm(`Are you sure you want to delete branch "${branchName}"?`)) {
        $.ajax({
            url: `/api/projects/${projectName}/branches/${branchName}`,
            method: 'DELETE',
            success: function () {
                Toast.show('Branch deleted successfully', 'success');
                location.reload();
            },
            error: function (xhr) {
                Toast.show(`Failed to delete branch: ${xhr.responseText}`, 'error');
            }
        });
    }
}

// Access Control
function addReference() {
    const template = `
        <div class="card mb-3">
            <div class="card-header">
                <div class="input-group">
                    <input type="text" class="form-control" name="refPattern[]" placeholder="refs/heads/*">
                    <div class="input-group-append">
                        <button class="btn btn-outline-danger" type="button" onclick="$(this).closest('.card').remove()">
                            <i class="fas fa-times"></i>
                        </button>
                    </div>
                </div>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-sm">
                        <thead>
                            <tr>
                                <th>Group</th>
                                <th>Read</th>
                                <th>Write</th>
                                <th>Submit</th>
                                <th>Force Push</th>
                                <th>Actions</th>
                        </thead>
                        <tbody>
                            <tr>
                                <td>
                                    <select class="form-control form-control-sm" name="group[]">
                                        ${groups.map(g => `<option value="${g.id}">${g.name}</option>`).join('')}
                                    </select>
                                </td>
                                <td><input type="checkbox" name="read[]"></td>
                                <td><input type="checkbox" name="write[]"></td>
                                <td><input type="checkbox" name="submit[]"></td>
                                <td><input type="checkbox" name="forcePush[]"></td>
                                <td>
                                    <button class="btn btn-sm btn-outline-danger" onclick="$(this).closest('tr').remove()">
                                        <i class="fas fa-times"></i>
                                    </button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
    $('.reference-access').append(template);
}

function removeAccess(refPattern, groupName) {
    if (confirm(`Remove access for "${groupName}" on "${refPattern}"?`)) {
        $.ajax({
            url: `/api/projects/${projectName}/access`,
            method: 'DELETE',
            data: { refPattern, groupName },
            success: function () {
                Toast.show('Access removed successfully', 'success');
                location.reload();
            },
            error: function (xhr) {
                Toast.show(`Failed to remove access: ${xhr.responseText}`, 'error');
            }
        });
    }
}

// Submit Rules
function addApproval() {
    const template = `
        <div class="approval-rule mb-3">
            <div class="input-group">
                <select class="form-control" name="label[]">
                    <option value="Code-Review">Code Review</option>
                    <option value="Verified">Verified</option>
                </select>
                <select class="form-control" name="value[]">
                    <option value="+2">+2</option>
                    <option value="+1">+1</option>
                </select>
                <div class="input-group-append">
                    <button class="btn btn-outline-danger" type="button" onclick="$(this).closest('.approval-rule').remove()">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
            </div>
        </div>
    `;
    $('.required-approvals').append(template);
}

function removeApproval(button) {
    $(button).closest('.approval-rule').remove();
}

// Webhooks
function editWebhook(webhookId) {
    $.get(`/api/projects/${projectName}/webhooks/${webhookId}`, function (webhook) {
        const modal = $('#createWebhookModal');
        modal.find('[name="url"]').val(webhook.url);
        modal.find('[name="events[]"]').each(function () {
            $(this).prop('checked', webhook.events.includes($(this).val()));
        });
        modal.find('[name="active"]').prop('checked', webhook.active);
        modal.find('form')
            .attr('action', `/api/projects/${projectName}/webhooks/${webhookId}`)
            .append('<input type="hidden" name="_method" value="PUT">');
        modal.modal('show');
    });
}

function deleteWebhook(webhookId) {
    if (confirm('Are you sure you want to delete this webhook?')) {
        $.ajax({
            url: `/api/projects/${projectName}/webhooks/${webhookId}`,
            method: 'DELETE',
            success: function () {
                Toast.show('Webhook deleted successfully', 'success');
                location.reload();
            },
            error: function (xhr) {
                Toast.show(`Failed to delete webhook: ${xhr.responseText}`, 'error');
            }
        });
    }
}

// Form Validation and Submission
$(document).ready(function () {
    // Branch name validation
    $('[name="name"]').on('input', function () {
        const value = $(this).val();
        const isValid = /^[a-zA-Z0-9_\/-]+$/.test(value);
        $(this).toggleClass('is-invalid', !isValid);
        $(this).closest('form').find('button[type="submit"]').prop('disabled', !isValid);
    });

    // Webhook URL validation
    $('[name="url"]').on('input', function () {
        const value = $(this).val();
        const isValid = /^https?:\/\/.+/.test(value);
        $(this).toggleClass('is-invalid', !isValid);
        $(this).closest('form').find('button[type="submit"]').prop('disabled', !isValid);
    });

    // Form submission with AJAX
    $('form').on('submit', function (e) {
        e.preventDefault();
        const form = $(this);
        const submitButton = form.find('button[type="submit"]');
        submitButton.prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Saving...');

        $.ajax({
            url: form.attr('action'),
            method: form.attr('method') || 'POST',
            data: form.serialize(),
            success: function (response) {
                Toast.show('Changes saved successfully', 'success');
                if (form.closest('.modal').length) {
                    form.closest('.modal').modal('hide');
                    location.reload();
                }
            },
            error: function (xhr) {
                Toast.show(`Failed to save changes: ${xhr.responseText}`, 'error');
            },
            complete: function () {
                submitButton.prop('disabled', false).text(submitButton.data('original-text') || 'Save Changes');
            }
        });
    });

    // Initialize tooltips
    $('[data-toggle="tooltip"]').tooltip();

    // Save button text for restoration
    $('button[type="submit"]').each(function () {
        $(this).data('original-text', $(this).text());
    });

    // Handle merge strategy change
    $('[name="mergeStrategy"]').change(function () {
        const strategy = $(this).val();
        $('#requireLinearHistory').closest('.form-group').toggle(strategy === 'rebase');
    });

    // Initialize merge strategy visibility
    $('[name="mergeStrategy"]').trigger('change');

    // Cherry-pick form handling
    $('#cherryPickForm').on('submit', function (e) {
        e.preventDefault();
        const commit = $(this).find('[name="commit"]').val();
        const targetBranch = $(this).find('[name="targetBranch"]').val();

        GitOperations.cherryPick(commit, targetBranch)
            .then(() => {
                Toast.show('Cherry-pick completed successfully', 'success');
                $('#cherryPickModal').modal('hide');
                location.reload();
            })
            .catch(xhr => Toast.show(`Cherry-pick failed: ${xhr.responseText}`, 'error'));
    });

    // Revert form handling
    $('#revertForm').on('submit', function (e) {
        e.preventDefault();
        const commit = $(this).find('[name="commit"]').val();
        const targetBranch = $(this).find('[name="targetBranch"]').val();

        GitOperations.revert(commit, targetBranch)
            .then(() => {
                Toast.show('Revert completed successfully', 'success');
                $('#revertModal').modal('hide');
                location.reload();
            })
            .catch(xhr => Toast.show(`Revert failed: ${xhr.responseText}`, 'error'));
    });

    // Tag form handling
    $('#tagForm').on('submit', function (e) {
        e.preventDefault();
        const name = $(this).find('[name="name"]').val();
        const commit = $(this).find('[name="commit"]').val();
        const message = $(this).find('[name="message"]').val();
        const signed = $(this).find('[name="signed"]').prop('checked');

        GitOperations.tag(name, commit, message, signed)
            .then(() => {
                Toast.show('Tag created successfully', 'success');
                $('#tagModal').modal('hide');
                location.reload();
            })
            .catch(xhr => Toast.show(`Failed to create tag: ${xhr.responseText}`, 'error'));
    });

    // Repository maintenance
    $('#gcButton').click(function () {
        if (confirm('Run garbage collection on this repository?')) {
            GitOperations.gc()
                .then(() => Toast.show('Garbage collection completed', 'success'))
                .catch(xhr => Toast.show(`GC failed: ${xhr.responseText}`, 'error'));
        }
    });

    $('#fsckButton').click(function () {
        if (confirm('Run repository integrity check?')) {
            GitOperations.fsck()
                .then(() => Toast.show('Repository check completed', 'success'))
                .catch(xhr => Toast.show(`Check failed: ${xhr.responseText}`, 'error'));
        }
    });
});

// Git Operations
const GitOperations = {
    createBranch: function (name, startPoint, protected) {
        return $.ajax({
            url: `/api/projects/${projectName}/branches`,
            method: 'POST',
            data: { name, startPoint, protected }
        });
    },

    deleteBranch: function (name) {
        return $.ajax({
            url: `/api/projects/${projectName}/branches/${name}`,
            method: 'DELETE'
        });
    },

    renameBranch: function (oldName, newName) {
        return $.ajax({
            url: `/api/projects/${projectName}/branches/${oldName}/rename`,
            method: 'POST',
            data: { newName }
        });
    },

    setBranchProtection: function (name, protected) {
        return $.ajax({
            url: `/api/projects/${projectName}/branches/${name}/protect`,
            method: 'PUT',
            data: { protected }
        });
    },

    mergeBranch: function (source, target, strategy) {
        return $.ajax({
            url: `/api/projects/${projectName}/merge`,
            method: 'POST',
            data: { source, target, strategy }
        });
    },

    cherryPick: function (commit, targetBranch) {
        return $.ajax({
            url: `/api/projects/${projectName}/cherry-pick`,
            method: 'POST',
            data: { commit, targetBranch }
        });
    },

    revert: function (commit, targetBranch) {
        return $.ajax({
            url: `/api/projects/${projectName}/revert`,
            method: 'POST',
            data: { commit, targetBranch }
        });
    },

    tag: function (name, commit, message, signed) {
        return $.ajax({
            url: `/api/projects/${projectName}/tags`,
            method: 'POST',
            data: { name, commit, message, signed }
        });
    },

    deleteTag: function (name) {
        return $.ajax({
            url: `/api/projects/${projectName}/tags/${name}`,
            method: 'DELETE'
        });
    },

    createArchive: function (ref, format) {
        return $.ajax({
            url: `/api/projects/${projectName}/archive`,
            method: 'POST',
            data: { ref, format }
        });
    },

    gc: function () {
        return $.ajax({
            url: `/api/projects/${projectName}/gc`,
            method: 'POST'
        });
    },

    fsck: function () {
        return $.ajax({
            url: `/api/projects/${projectName}/fsck`,
            method: 'POST'
        });
    }
};

// UI Handlers for new operations
function showCherryPickModal(commit) {
    $('#cherryPickModal')
        .find('[name="commit"]').val(commit).end()
        .modal('show');
}

function showRevertModal(commit) {
    $('#revertModal')
        .find('[name="commit"]').val(commit).end()
        .modal('show');
}

function showTagModal(commit) {
    $('#tagModal')
        .find('[name="commit"]').val(commit).end()
        .modal('show');
}
