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
export 'src/mesh/mesh_node.dart';
export 'src/mesh/flood_router.dart';
export 'src/mesh/mesh_packet.dart';
export 'src/mesh/bloom_filter.dart';
export 'src/mesh/route_table.dart';
export 'src/mesh/mesh_config.dart';
export 'src/mesh/mesh_stats.dart';
export 'src/mesh/presence.dart';
export 'src/crypto/identity.dart';
export 'src/protocol/uuids.dart';
export 'src/protocol/frame_codec.dart';

