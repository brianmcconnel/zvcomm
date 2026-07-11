import '../transport/transport.dart';
import 'transport_plugin.dart';

/// Global registry of [TransportPlugin]s.
///
/// Built-in plugins register at app startup; third-party packages call
/// [register] from their library `init` or an explicit `registerPlugins()`.
final class TransportRegistry {
  TransportRegistry._();

  static final TransportRegistry instance = TransportRegistry._();

  final Map<String, TransportPlugin> _plugins = {};

  /// All registered plugins sorted by descending [TransportPlugin.priority].
  List<TransportPlugin> get plugins {
    final list = _plugins.values.toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return List.unmodifiable(list);
  }

  TransportPlugin? operator [](String id) => _plugins[id];

  bool contains(String id) => _plugins.containsKey(id);

  /// Register or replace a plugin by [TransportPlugin.id].
  void register(TransportPlugin plugin) {
    _plugins[plugin.id] = plugin;
  }

  void registerAll(Iterable<TransportPlugin> plugins) {
    for (final p in plugins) {
      register(p);
    }
  }

  /// Remove a plugin. Does not dispose live transports.
  bool unregister(String id) => _plugins.remove(id) != null;

  void clear() => _plugins.clear();

  /// Create transports for enabled plugin ids (or all [enabledByDefault]).
  List<Transport> createStack({
    required TransportPluginContext context,
    Set<String>? enabledIds,
  }) {
    final out = <Transport>[];
    for (final plugin in plugins) {
      final enabled = enabledIds != null
          ? enabledIds.contains(plugin.id)
          : plugin.enabledByDefault;
      if (!enabled) continue;
      out.add(plugin.create(context));
    }
    return out;
  }
}
