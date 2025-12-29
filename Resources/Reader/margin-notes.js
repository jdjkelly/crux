// CruxMarginNotes - Margin note rendering and interaction
const CruxMarginNotes = {
    notes: new Map(),
    marginLeft: null,
    marginRight: null,

    init: function() {
        this.marginLeft = document.querySelector('.crux-margin-left');
        this.marginRight = document.querySelector('.crux-margin-right');
        this.setupEventDelegation();
    },

    activeNoteId: null,
    floatingInput: null,

    setActiveNote: function(noteId) {
        // Clear previous active
        const prev = document.querySelector('.crux-margin-note.active');
        if (prev) prev.classList.remove('active');

        this.activeNoteId = noteId;

        if (!this.floatingInput) {
            this.floatingInput = document.querySelector('.crux-floating-input');
        }

        const contextEl = this.floatingInput.querySelector('.crux-floating-input-context');
        const inputEl = this.floatingInput.querySelector('input');

        if (noteId) {
            const note = this.notes.get(noteId);
            if (note && note.querySelector('.thread-content')) {
                note.classList.add('active');

                // Extract preview text from the note
                const selectedText = note.querySelector('.selected-passage');
                if (selectedText && contextEl) {
                    const text = selectedText.textContent.trim();
                    const preview = text.length > 50 ? text.substring(0, 50) + '...' : text;
                    contextEl.textContent = 'Replying to: "' + preview + '"';
                }

                this.floatingInput.classList.add('visible');
                inputEl.focus();
            }
        } else {
            this.floatingInput.classList.remove('visible');
            inputEl.value = '';
            if (contextEl) contextEl.textContent = '';
        }
    },

    setupEventDelegation: function() {
        document.addEventListener('click', (e) => {
            const deleteBtn = e.target.closest('.crux-delete-highlight');
            if (deleteBtn) {
                const note = deleteBtn.closest('.crux-margin-note');
                const highlightId = note.dataset.highlightId;
                window.webkit.messageHandlers.marginNoteAction.postMessage({
                    action: 'deleteHighlight',
                    highlightId: highlightId
                });
                CruxHighlighter.removeHighlight(highlightId);
                this.removeNote(highlightId);
                if (this.activeNoteId === highlightId) this.setActiveNote(null);
                return;
            }

            const commitBtn = e.target.closest('.crux-commit-highlight');
            if (commitBtn) {
                const note = commitBtn.closest('.crux-margin-note');
                window.webkit.messageHandlers.marginNoteAction.postMessage({
                    action: 'commitHighlight',
                    highlightId: note.dataset.highlightId
                });
                return;
            }

            const startBtn = e.target.closest('.crux-start-thread');
            if (startBtn) {
                const note = startBtn.closest('.crux-margin-note');
                window.webkit.messageHandlers.marginNoteAction.postMessage({
                    action: 'startThread',
                    highlightId: note.dataset.highlightId
                });
                return;
            }

            // Click on note with thread -> activate for reply
            const note = e.target.closest('.crux-margin-note');
            if (note && note.querySelector('.thread-content')) {
                this.setActiveNote(note.dataset.highlightId);
                return;
            }

            // Click outside -> deactivate
            if (!e.target.closest('.crux-floating-input')) {
                this.setActiveNote(null);
            }
        });

        document.addEventListener('keydown', (e) => {
            // Handle Enter on floating input
            if (e.key === 'Enter' && this.activeNoteId) {
                const input = e.target.closest('.crux-floating-input input');
                if (input && input.value.trim()) {
                    e.preventDefault();
                    window.webkit.messageHandlers.marginNoteAction.postMessage({
                        action: 'sendFollowUp',
                        highlightId: this.activeNoteId,
                        message: input.value.trim()
                    });
                    input.value = '';
                    return;
                }
            }

            // Escape -> deactivate
            if (e.key === 'Escape') {
                this.setActiveNote(null);
                return;
            }

            // Keyboard shortcuts for pending selection
            if (e.metaKey && this.pendingHighlightId) {
                if (e.key === 'h' || e.key === 'H') {
                    e.preventDefault();
                    window.webkit.messageHandlers.marginNoteAction.postMessage({
                        action: 'commitHighlight',
                        highlightId: this.pendingHighlightId
                    });
                } else if (e.key === 'a' || e.key === 'A') {
                    e.preventDefault();
                    window.webkit.messageHandlers.marginNoteAction.postMessage({
                        action: 'startThread',
                        highlightId: this.pendingHighlightId
                    });
                }
            }
        });
    },

    pendingHighlightId: null,

    createNoteForHighlight: function(highlightId, preview) {
        const highlight = document.querySelector('[data-highlight-id="' + highlightId + '"]');
        if (!highlight || !this.marginRight) return;

        this.removeNote(highlightId);

        const top = this.getDocumentOffset(highlight);

        const note = document.createElement('div');
        note.className = 'crux-margin-note';
        note.dataset.highlightId = highlightId;
        note.dataset.idealTop = top;
        note.dataset.side = 'right';
        note.style.top = top + 'px';

        note.innerHTML = '<div class="preview">' + this.escapeHTML(preview) + '</div>' +
            '<button class="crux-start-thread">Annotate</button>';

        this.marginRight.appendChild(note);
        this.notes.set(highlightId, note);

        requestAnimationFrame(() => this.resolveCollisions());
    },

    updateNotes: function(notesData) {
        // Ensure margins are initialized
        if (!this.marginRight || !this.marginLeft) {
            this.marginLeft = document.querySelector('.crux-margin-left');
            this.marginRight = document.querySelector('.crux-margin-right');
        }
        if (!this.marginRight) return;

        // Track pending highlight ID for keyboard shortcuts
        this.pendingHighlightId = null;

        // Remove notes that are no longer in the data (e.g., old pending selection)
        const newIds = new Set(notesData.map(d => d.highlightId));
        for (const [highlightId, note] of this.notes) {
            if (!newIds.has(highlightId)) {
                this.removeNote(highlightId);
            }
        }

        for (const data of notesData) {
            // Track uncommitted selection for keyboard shortcuts
            if (!data.isCommitted) {
                this.pendingHighlightId = data.highlightId;
            }

            let note = this.notes.get(data.highlightId);

            if (!note) {
                const highlight = document.querySelector('[data-highlight-id="' + data.highlightId + '"]');
                if (!highlight) continue;

                note = document.createElement('div');
                note.className = 'crux-margin-note';
                note.dataset.highlightId = data.highlightId;
                note.dataset.idealTop = this.getDocumentOffset(highlight);
                note.dataset.side = 'right';
                note.style.top = note.dataset.idealTop + 'px';
                this.marginRight.appendChild(note);
                this.notes.set(data.highlightId, note);
            }

            note.innerHTML = this.buildNoteContent(data);
        }

        requestAnimationFrame(() => this.resolveCollisions());
    },

    buildNoteContent: function(data) {
        let html = '<div class="note-header"><div class="preview">' + this.escapeHTML(data.previewText) + '</div>';
        html += '<button class="crux-delete-highlight" title="Delete">\u00d7</button></div>';

        if (data.isLoading) {
            html += '<div class="crux-loading">' + (data.hasThread ? 'Thinking...' : 'Analyzing...') + '</div>';
        } else if (data.hasThread && data.threadContent) {
            html += '<div class="thread-content">' + data.threadContent + '</div>';
            // No inline input - using floating input bar instead
        } else if (!data.isCommitted) {
            // Uncommitted selection - show both buttons
            html += '<div class="crux-selection-actions">' +
                '<button class="crux-commit-highlight">Highlight</button>' +
                '<button class="crux-start-thread">Annotate</button>' +
                '</div>';
        } else {
            // Committed but no thread
            html += '<button class="crux-start-thread">Annotate</button>';
        }

        return html;
    },

    removeNote: function(highlightId) {
        const note = this.notes.get(highlightId);
        if (note) {
            note.remove();
            this.notes.delete(highlightId);
        }
    },

    clearAllNotes: function() {
        for (const note of this.notes.values()) {
            note.remove();
        }
        this.notes.clear();
    },

    getDocumentOffset: function(el) {
        let top = 0;
        let current = el;
        while (current && current !== document.body) {
            top += current.offsetTop;
            current = current.offsetParent;
        }
        return top;
    },

    resolveCollisions: function() {
        // Ensure margins are initialized
        if (!this.marginRight || !this.marginLeft) {
            this.marginLeft = document.querySelector('.crux-margin-left');
            this.marginRight = document.querySelector('.crux-margin-right');
        }
        if (!this.marginRight || !this.marginLeft) return;

        const notesList = Array.from(this.notes.values())
            .map(el => ({
                el: el,
                idealTop: parseFloat(el.dataset.idealTop) || 0,
                height: el.offsetHeight
            }))
            .sort((a, b) => a.idealTop - b.idealTop);

        const GAP = 8;
        const OVERLAP_THRESHOLD = 40; // Move to left if would be pushed down more than this
        let rightBottom = 0;
        let leftBottom = 0;

        for (const note of notesList) {
            const wouldBeOnRight = Math.max(note.idealTop, rightBottom);
            const pushAmount = wouldBeOnRight - note.idealTop;

            // If note would be pushed down significantly, try left side
            if (pushAmount > OVERLAP_THRESHOLD && note.idealTop >= leftBottom) {
                // Move to left side
                if (note.el.dataset.side !== 'left') {
                    note.el.dataset.side = 'left';
                    this.marginLeft.appendChild(note.el);
                }
                const resolvedTop = Math.max(note.idealTop, leftBottom);
                note.el.style.top = resolvedTop + 'px';
                leftBottom = resolvedTop + note.height + GAP;
            } else {
                // Keep on right side
                if (note.el.dataset.side !== 'right') {
                    note.el.dataset.side = 'right';
                    this.marginRight.appendChild(note.el);
                }
                note.el.style.top = wouldBeOnRight + 'px';
                rightBottom = wouldBeOnRight + note.height + GAP;
            }
        }
    },

    escapeHTML: function(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }
};

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => CruxMarginNotes.init());
} else {
    CruxMarginNotes.init();
}
