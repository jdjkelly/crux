// macOS: Use mouseup for selection detection
document.addEventListener('mouseup', function(e) {
    // Ignore selections within margin notes
    if (e.target.closest('.crux-margin-note') || e.target.closest('.crux-margin')) {
        return;
    }
    const cfiData = CruxCFI.getSelectionCFI();
    if (cfiData && cfiData.text.length > 0) {
        window.webkit.messageHandlers.textSelection.postMessage(cfiData);
    }
});
