import 'backend.dart';
import '../models.dart';

Future<LameBackend> loadBackend() async =>
    throw const LameException(-100, 'lame has no backend on this platform');
