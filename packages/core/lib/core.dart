/// ZVComm core: transport abstraction, mesh primitives, models, and crypto interfaces.
///
/// All types are pure Dart so they can run on device, in tests, and in the
/// discrete-event simulator without platform plugins.
library;

export 'src/models/peer.dart';
export 'src/models/message.dart';
export 'src/models/transport_kind.dart';
export 'src/transport/transport.dart';
export 'src/transport/connection.dart';
export 'src/transport/mock_transport.dart';
export 'src/transport/transport_manager.dart';
export 'src/plugins/transport_plugin.dart';
export 'src/plugins/transport_registry.dart';
export 'src/plugins/hardware_adapter.dart';
export 'src/plugins/adapter_transport.dart';
export 'src/plugins/stub_transports.dart';
export 'src/plugins/builtin_plugins.dart';
export 'src/mesh/mesh_node.dart';
export 'src/mesh/flood_router.dart';
export 'src/mesh/mesh_packet.dart';
export 'src/mesh/bloom_filter.dart';
export 'src/mesh/route_table.dart';
export 'src/mesh/mesh_config.dart';
export 'src/mesh/mesh_stats.dart';
export 'src/mesh/presence.dart';
export 'src/crypto/identity.dart';
export 'src/crypto/secure_session.dart';
export 'src/crypto/identity_store.dart';
export 'src/crypto/enrollment.dart';
export 'src/crypto/credential_exchange.dart';
export 'src/mesh/secure_mesh.dart';
export 'src/transfer/file_transfer.dart';
export 'src/chat/chat_log.dart';
export 'src/chat/message_censor.dart';
export 'src/protocol/uuids.dart';
export 'src/protocol/frame_codec.dart';
