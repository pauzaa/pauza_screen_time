# Error model

The plugin emits only stable taxonomy `PlatformException.code` values.

## Stable taxonomy codes

- `UNSUPPORTED`
- `MISSING_PERMISSION`
- `PERMISSION_DENIED`
- `SYSTEM_RESTRICTED`
- `INVALID_ARGUMENT`
- `INTERNAL_FAILURE`

## Error details contract

All plugin errors include a `details` map with:

- required: `feature`, `action`, `platform`
- optional: `missing`, `status`, `diagnostic`

There is no legacy code compatibility layer.

## Typed exception usage

Plugin APIs return the expected value type on success and throw typed `PauzaError` on failure.

```dart
final restrictions = AppRestrictionManager();
try {
  await restrictions.restrictApps(identifiers);
} on PauzaMissingPermissionError catch (error) {
  // Show permission guidance UI.
  // error.details contains structured diagnostics.
}
```

## Fast-failure behavior

Channel payload decoding is strict. Malformed or unexpected payloads from native
layers are treated as `INTERNAL_FAILURE` and surfaced as typed
`PauzaInternalFailureError` in Dart.
