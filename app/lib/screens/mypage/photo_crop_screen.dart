import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../utils/design_tokens.dart';

/// 인스타그램식 이미지 선택 + 1:1 크롭 화면.
/// 상단: 고정 1:1 크롭 뷰포트(이미지 pan/zoom) / 하단: 갤러리 썸네일 그리드.
/// 네이티브 uCrop 미사용 → Android 15 edge-to-edge status bar 겹침 회피.
/// 결과: 크롭된 JPEG bytes(Uint8List)를 Navigator.pop으로 반환.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key});

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _cropController = CropController();
  List<AssetEntity> _assets = [];
  AssetEntity? _selected;
  Uint8List? _currentBytes; // 크롭 대상 원본 bytes
  bool _loading = true;
  bool _denied = false;
  bool _cropping = false;
  final Map<String, Uint8List> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) setState(() { _denied = true; _loading = false; });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    final recent = albums.first;
    final assets = await recent.getAssetListPaged(page: 0, size: 100);
    Uint8List? first;
    if (assets.isNotEmpty) first = await assets.first.originBytes;
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _selected = assets.isNotEmpty ? assets.first : null;
      _currentBytes = first;
      _loading = false;
    });
  }

  Future<void> _selectAsset(AssetEntity a) async {
    if (a == _selected) return;
    final b = await a.originBytes;
    if (!mounted) return;
    setState(() { _selected = a; _currentBytes = b; });
  }

  void _confirm() {
    if (_currentBytes == null || _cropping) return;
    setState(() => _cropping = true);
    _cropController.crop();
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    if (result is CropSuccess) {
      Navigator.of(context).pop(result.croppedImage);
    } else {
      setState(() => _cropping = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 크롭 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          // ── 헤더 ──
          SizedBox(
            height: 52,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              const Text('사진 선택',
                  style: TextStyle(color: Colors.white, fontSize: Typo.title, fontWeight: Typo.bold)),
              const Spacer(),
              _cropping
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                  : TextButton(
                      onPressed: _currentBytes == null ? null : _confirm,
                      child: Text('완료',
                          style: TextStyle(
                              color: _currentBytes == null ? Colors.white38 : const Color(0xFF3897F0),
                              fontSize: Typo.subtitle, fontWeight: Typo.extra)),
                    ),
            ]),
          ),
          // ── 1:1 크롭 뷰포트 (고정 틀, 이미지 pan/zoom) ──
          SizedBox(
            width: w,
            height: w,
            child: _currentBytes == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Crop(
                    image: _currentBytes!,
                    controller: _cropController,
                    onCropped: _onCropped,
                    aspectRatio: 1,
                    withCircleUi: false,
                    interactive: true,    // 핀치 줌 / 드래그
                    fixCropRect: true,    // 크롭 틀 고정 → 이미지가 움직임 (인스타식)
                    // 크롭 틀을 이미지 내부 최대 중앙 정사각형으로 초기화
                    // → crop ⊆ image 항상 보장 → 틀 밖(여백)으로 이동 불가, pan/zoom은 이미지 내에서 clamp
                    initialRectBuilder: InitialRectBuilder.withBuilder((viewportRect, imageRect) {
                      final side = imageRect.width < imageRect.height ? imageRect.width : imageRect.height;
                      final left = imageRect.left + (imageRect.width - side) / 2;
                      final top = imageRect.top + (imageRect.height - side) / 2;
                      return Rect.fromLTWH(left, top, side, side);
                    }),
                    baseColor: Colors.black,
                    maskColor: Colors.black.withValues(alpha: 0.55),
                    radius: 0,
                    cornerDotBuilder: (size, edge) => const SizedBox.shrink(),
                    progressIndicator: const CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          // ── 갤러리 그리드 ──
          Expanded(child: _buildGallery()),
        ]),
      ),
    );
  }

  Widget _buildGallery() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_denied) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('사진 접근 권한이 필요합니다',
              style: TextStyle(color: Colors.white70, fontSize: Typo.body)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            child: const Text('설정 열기', style: TextStyle(color: Color(0xFF3897F0))),
          ),
        ]),
      );
    }
    if (_assets.isEmpty) {
      return const Center(child: Text('사진이 없습니다', style: TextStyle(color: Colors.white70)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final a = _assets[i];
        final sel = a == _selected;
        return GestureDetector(
          onTap: () => _selectAsset(a),
          child: Stack(fit: StackFit.expand, children: [
            _Thumb(asset: a, cache: _thumbCache),
            if (sel)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF3897F0), width: 3),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// 썸네일 (메모리 캐시)
class _Thumb extends StatefulWidget {
  final AssetEntity asset;
  final Map<String, Uint8List> cache;
  const _Thumb({required this.asset, required this.cache});
  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = widget.cache[widget.asset.id];
    if (cached != null) { setState(() => _data = cached); return; }
    final d = await widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(220));
    if (d != null) widget.cache[widget.asset.id] = d;
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return Container(color: const Color(0xFF1A1A1A));
    return Image.memory(_data!, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
