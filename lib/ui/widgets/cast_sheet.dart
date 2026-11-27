import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/cast/dlna.dart';

/// 投屏设备列表。发现是真 SSDP，找不到设备就说原版那句话，不列假设备。
Future<DlnaDevice?> showCastSheet(BuildContext context) => showDialog<DlnaDevice>(
  context: context,
  builder: (_) => const _CastSheet(),
);

class _CastSheet extends StatefulWidget {
  const _CastSheet();

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  List<DlnaDevice> _devices = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    try {
      final devices = await Dlna.discover();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } on DlnaException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '投屏',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: LcbColors.text,
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LcbColors.primary,
                      ),
                    ),
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: LcbColors.sysRed),
                )
              else if (_devices.isEmpty)
                const Text(
                  '没有找到设备。请确认电视/盒子和手机连着同一个 Wi-Fi，并已打开 DLNA（多屏互动、无线投屏）功能。',
                  style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (_, index) {
                      final device = _devices[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.cast, size: 18),
                        title: Text(device.name),
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
