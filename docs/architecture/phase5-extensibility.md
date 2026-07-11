# Phase 5 – Extensibility

## Goals

- Pluggable transports without forking mesh code
- Hot enable/disable of backends at runtime
- Hardware adapters (serial, USB, custom radio) as first-class mesh links
- Stubs for future UWB / LoRa

## Transport plugins

```dart
abstract class TransportPlugin {
  String get id;           // e.g. builtin.ble
  String get name;
  TransportKind get kind;
  int get priority;
  Transport create(TransportPluginContext context);
}
```

Register:

```dart
TransportRegistry.instance.register(myPlugin);
// or
registerBlePlugin();
registerNfcPlugin();
registerWifiPlugin();
BuiltinCorePlugins.registerAll();
```

Build a stack:

```dart
final ctx = TransportPluginContext(localId: id, displayName: 'Phone');
final transports = TransportRegistry.instance.createStack(
  context: ctx,
  enabledIds: {'builtin.ble', 'builtin.wifi'},
);
final mgr = TransportManager(transports);
```

### Built-in plugin ids

| Id | Package | Default |
|----|---------|---------|
| `builtin.ble` | ble | on |
| `builtin.nfc` | nfc | on |
| `builtin.wifi` | wifi | on |
| `builtin.mock` | core | off (options.medium) |
| `builtin.hardware_adapter` | core | off (options.adapter) |
| `builtin.uwb.stub` | core | off |
| `builtin.lora.stub` | core | off |

## Hot-plug

`TransportManager.register` / `unregister` attach or detach a live `Transport`
while discovery/advertising is active. The app Settings screen toggles plugins
via `MeshController.setPluginEnabled`.

## Hardware adapters

```dart
abstract class HardwareAdapter {
  Future<void> open();
  Future<void> write(Uint8List data);
  Stream<Uint8List> get inbound;
}
```

Wrap with `AdapterTransport` (length-prefixed frames via `StreamFrameCodec`).

`LoopbackHardwarePair` provides two linked adapters for tests without radios.

### Adding a serial radio (sketch)

1. Implement `HardwareAdapter` with platform serial I/O (FFI/plugin of your choice, permissive license).
2. Register:

```dart
registry.register(SimpleTransportPlugin(
  id: 'vendor.serial_lora',
  name: 'Serial LoRa',
  kind: TransportKind.lora,
  priority: 25,
  factory: (ctx) => AdapterTransport(
    adapter: ctx.option<HardwareAdapter>('adapter')!,
    kind: TransportKind.lora,
  ),
));
```

3. Pass the open adapter in `TransportPluginContext.options`.

## Third-party packages

Create a Dart/Flutter package that depends on `core`, exports
`void registerMyPlugin()`, and document that hosts must call it at startup
before `MeshController.bootstrap()`.

## Testing

See `packages/core/test` — registry ordering, hot-plug, hardware loopback
mesh chat.
