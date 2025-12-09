## 1.0.1

- **Fixed**: Automatic data flushing now works correctly by default
  - `PagedStorage.close()` always flushes data to disk
  - No manual `flush()` call required before closing the database
  - `autoFlushOnClose` enabled by default in production and development configs
- **Added**: Comprehensive auto-flush tests to verify persistence behavior
- **Docs**: Clarified nested model serialization patterns

## 1.0.0

- Initial version.
