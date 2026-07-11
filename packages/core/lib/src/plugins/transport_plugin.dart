import '../models/transport_kind.dart';
import '../transport/transport.dart';

/// Runtime context passed when a plugin constructs a [Transport].
final class TransportPluginContext {
  /// Local mesh node id (stable device id).
  final String localId;

  /// Human-readable name for advertisements.
  final String? displayName;

  /// Plugin-specific options (ports, device paths, feature flags).
  final Map<String, Object?> options;

  const TransportPluginContext({
    required this.localId,
    this.displayName,
    this.options = const {},
  });

  T? option<T>(String key) {
    final v = options[key];
    if (v is T) return v;
    return null;
  }
}

/// Descriptor + factory for a pluggable transport backend.
///
/// Plugins register with [TransportRegistry]. The app (or tests) create
/// concrete [Transport] instances via [create] and hand them to
/// [TransportManager].
abstract class TransportPlugin {
  /// Stable plugin id (e.g. `builtin.ble`, `example.loopback`).
  String get id;

  /// UI label.
  String get name;

  /// Logical radio class.
  TransportKind get kind;

  /// Higher loads first when building default stacks (Wi-Fi > BLE > …).
  int get priority;

  /// Static capability advertisement for UI / feature gates.
  TransportCapabilities get capabilities;

  /// Optional description for settings screens.
  String get description => '';

  /// Whether this plugin is enabled by default when building a stack.
  bool get enabledByDefault => true;

  /// Construct a transport instance for [context].
  Transport create(TransportPluginContext context);
}

/// Function-based plugin for quick registration without a class.
final class SimpleTransportPlugin implements TransportPlugin {
  @override
  final String id;
  @override
  final String name;
  @override
  final TransportKind kind;
  @override
  final int priority;
  @override
  final TransportCapabilities capabilities;
  @override
  final String description;
  @override
  final bool enabledByDefault;

  final Transport Function(TransportPluginContext context) _factory;

  const SimpleTransportPlugin({
    required this.id,
    required this.name,
    required this.kind,
    required Transport Function(TransportPluginContext context) factory,
    this.priority = 0,
    this.capabilities = const TransportCapabilities(),
    this.description = '',
    this.enabledByDefault = true,
  }) : _factory = factory;

  @override
  Transport create(TransportPluginContext context) => _factory(context);
}
