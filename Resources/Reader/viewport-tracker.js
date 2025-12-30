// CruxViewportTracker - Tracks which chapter/subchapter is visible during scroll
const CruxViewportTracker = {
    observer: null,
    anchors: new Map(),          // anchorId -> { element, chapterIndex }
    visibleAnchors: new Set(),
    currentTopAnchor: null,
    debounceTimer: null,
    isProgrammaticNavigation: false,

    // Called by Swift with list of anchors to track
    // anchors: [{ id: string, chapterIndex: number, isFileStart: boolean }]
    init: function(anchorsToTrack) {
        this.cleanup();

        // Build anchor map from Swift-provided data
        for (const anchor of anchorsToTrack) {
            const element = anchor.isFileStart
                ? this.createDocStartSentinel(anchor.chapterIndex)
                : document.getElementById(anchor.id);
            if (element) {
                this.anchors.set(anchor.id, { element: element, chapterIndex: anchor.chapterIndex });
            }
        }

        if (this.anchors.size === 0) return;

        // Setup IntersectionObserver - track top 30% of viewport
        // rootMargin: top 10% ignored, bottom 60% ignored = middle 30% is "active zone"
        this.observer = new IntersectionObserver(
            (entries) => this.handleIntersection(entries),
            { root: null, rootMargin: '-10% 0px -60% 0px', threshold: 0 }
        );

        for (const [id, data] of this.anchors) {
            this.observer.observe(data.element);
        }
    },

    createDocStartSentinel: function(chapterIndex) {
        let sentinel = document.getElementById('__crux_doc_start__');
        if (!sentinel) {
            sentinel = document.createElement('div');
            sentinel.id = '__crux_doc_start__';
            sentinel.style.cssText = 'position:absolute;top:0;height:1px;width:1px;pointer-events:none;';
            document.body.insertBefore(sentinel, document.body.firstChild);
        }
        return sentinel;
    },

    handleIntersection: function(entries) {
        if (this.isProgrammaticNavigation) return;

        for (const entry of entries) {
            const anchorId = entry.target.id;
            if (entry.isIntersecting) {
                this.visibleAnchors.add(anchorId);
            } else {
                this.visibleAnchors.delete(anchorId);
            }
        }
        this.scheduleUpdate();
    },

    scheduleUpdate: function() {
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
        }
        this.debounceTimer = setTimeout(() => this.sendUpdate(), 100);
    },

    sendUpdate: function() {
        // Find topmost visible anchor (smallest y position that's near top of viewport)
        let topAnchor = null;
        let topY = Infinity;

        for (const anchorId of this.visibleAnchors) {
            const data = this.anchors.get(anchorId);
            if (!data) continue;
            const rect = data.element.getBoundingClientRect();
            // Allow slightly above viewport (-100px) to catch anchors just scrolled past
            if (rect.top < topY && rect.top >= -100) {
                topY = rect.top;
                topAnchor = { id: anchorId, chapterIndex: data.chapterIndex };
            }
        }

        // Fallback: find nearest anchor above viewport if nothing visible
        if (!topAnchor) {
            topAnchor = this.findNearestAbove();
        }

        // Only send if anchor changed
        if (topAnchor && topAnchor.id !== this.currentTopAnchor) {
            this.currentTopAnchor = topAnchor.id;
            window.webkit.messageHandlers.visibleSection.postMessage({
                anchorId: topAnchor.id,
                chapterIndex: topAnchor.chapterIndex
            });
        }
    },

    findNearestAbove: function() {
        let nearest = null;
        let nearestY = -Infinity;

        for (const [id, data] of this.anchors) {
            const rect = data.element.getBoundingClientRect();
            // Find anchor that's above viewport (negative bottom) but closest to top
            if (rect.bottom < 0 && rect.bottom > nearestY) {
                nearestY = rect.bottom;
                nearest = { id: id, chapterIndex: data.chapterIndex };
            }
        }

        return nearest;
    },

    // Called by Swift before programmatic navigation (TOC click, arrow keys)
    beginProgrammaticNavigation: function() {
        this.isProgrammaticNavigation = true;
    },

    // Called by Swift after programmatic navigation settles
    endProgrammaticNavigation: function() {
        setTimeout(() => {
            this.isProgrammaticNavigation = false;
            // Force an update check after navigation settles
            this.sendUpdate();
        }, 300);
    },

    cleanup: function() {
        if (this.observer) {
            this.observer.disconnect();
            this.observer = null;
        }
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
            this.debounceTimer = null;
        }
        this.anchors.clear();
        this.visibleAnchors.clear();
        this.currentTopAnchor = null;

        // Remove sentinel if exists
        const sentinel = document.getElementById('__crux_doc_start__');
        if (sentinel) sentinel.remove();
    }
};
