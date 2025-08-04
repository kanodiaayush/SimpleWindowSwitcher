# SimpleWindowSwitcher - Commit Testing Log

## Purpose
Track which commits have working window switching functionality to identify when the feature broke.

## Commit History (newest to oldest)
```
22f3c1d (HEAD -> main) Add code signing and permission persistence improvements
72bac13 Fix window switching behavior with proper MRU selection  
6b99dbf Update install script to use system Applications folder
bede8a4 Add installation script for easy setup
ebfa0af Add dock icon and proper quit functionality
f0f4392 Implement Most Recently Used (MRU) window ordering
29698dc Add ESC key to cancel window switching
18ca26b Fix up/down arrow key navigation for proper grid movement
69c9a5c Performance optimizations: Add caching, lazy loading, and concurrent processing
bf829e3 Complete enhanced window switcher implementation
```

## Testing Results

### Current Status (22f3c1d) - ❌ BROKEN
- **Issue**: Window switching not working for any apps (Slack, Chrome, etc.)
- **Symptoms**: AX API calls report success but windows don't actually come to front
- **Output**: All operations show success but no visual window switching occurs

### Testing ebfa0af - "Add dock icon and proper quit functionality" - ❌ STILL BROKEN
- **Date**: Just tested
- **Status**: Window switching still not working
- **Notes**: This was before MRU ordering implementation, but still broken

### Testing f0f4392 - "Implement Most Recently Used (MRU) window ordering" - ❌ STILL BROKEN
- **Date**: Just tested
- **Status**: Window switching still not working
- **Notes**: Even the MRU implementation commit doesn't work

### Testing 29698dc - "Add ESC key to cancel window switching" - ✅ WORKING!
- **Date**: Just tested
- **Status**: Window switching WORKS! 
- **Notes**: This is the last working version
- **Issue**: Arrow keys are being passed to underlying apps instead of being captured by switcher

---

## Notes
- **FOUND**: Last working commit is 29698dc - "Add ESC key to cancel window switching"
- **BROKEN**: MRU ordering implementation (f0f4392) broke window activation
- **CURRENT ISSUE**: Arrow keys leak through to underlying apps instead of being captured
- **NEXT**: Fix arrow key capture while preserving working window switching