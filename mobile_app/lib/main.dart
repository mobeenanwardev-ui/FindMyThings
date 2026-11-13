import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera_macos/camera_macos.dart';
import 'ai_model_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

// Camera pixel conversion and JPEG encoding run away from Flutter's UI isolate.
// The model still receives a fixed 640x640 letterboxed image, preserving the
// camera frame's aspect ratio instead of stretching it.
Uint8List _encodeCameraFrame(Map<String, Object> message) {
  final transferableBytes = message['bytes'] as TransferableTypedData;
  final width = message['width'] as int;
  final height = message['height'] as int;
  final bytesPerRow = message['bytesPerRow'] as int;
  const modelSize = 640;
  final bytes = transferableBytes.materialize().asUint8List();
  final scale = math.min(modelSize / width, modelSize / height);
  final resizedWidth = (width * scale).round().clamp(1, modelSize).toInt();
  final resizedHeight = (height * scale).round().clamp(1, modelSize).toInt();
  final padX = (modelSize - resizedWidth) ~/ 2;
  final padY = (modelSize - resizedHeight) ~/ 2;
  // A three-channel image starts with black pixels, which form the
  // letterbox padding without an additional full-frame clearing pass.
  final canvas = img.Image(width: modelSize, height: modelSize, numChannels: 3);
  for (var y = 0; y < resizedHeight; y++) {
    final sourceY = (y * height / resizedHeight).floor();
    final row = sourceY * bytesPerRow;
    for (var x = 0; x < resizedWidth; x++) {
      final sourceX = (x * width / resizedWidth).floor();
      final offset = row + sourceX * 4;
      if (offset + 3 >= bytes.length) continue;
      canvas.setPixelRgb(
        padX + x,
        padY + y,
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 72));
}

void main() => runApp(const FindMyThingsApp());

const green = Color(0xFF17483B);
const cream = Color(0xFFF6F5EF);
const muted = Color(0xFF788078);

class FindMyThingsApp extends StatelessWidget {
  const FindMyThingsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FindMyThings',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green)),
    home: const HomePage(),
  );
}

class Belonging {
  const Belonging({required this.id, required this.name, required this.category, this.photo, required this.created});
  final String id, name, category;
  final String? photo;
  final DateTime created;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'category': category, 'photo': photo, 'created': created.toIso8601String()};
  factory Belonging.fromJson(Map<String, dynamic> j) => Belonging(
    id: j['id'], name: j['name'], category: j['category'] ?? 'Other',
    photo: j['photo'], created: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final List<Belonging> _items = [];
  Directory? _directory;
  bool _loading = true;
  int _tab = 0;
  String _search = '';

  List<Belonging> get _shown {
    final list = _items.where((x) => x.name.toLowerCase().contains(_search.toLowerCase()) || x.category.toLowerCase().contains(_search.toLowerCase())).toList();
    if (_tab == 1) list.sort((a,b) => b.created.compareTo(a.created));
    return list;
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      _directory = await getApplicationDocumentsDirectory();
      final file = File('${_directory!.path}/belongings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        _items.addAll(data.map((e) => Belonging.fromJson(Map<String,dynamic>.from(e))));
      }
    } catch (e) { debugPrint('Load error: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_directory == null) return;
    await File('${_directory!.path}/belongings.json').writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  Future<String> _copyPhoto(XFile photo) async {
    final folder = Directory('${_directory!.path}/belonging_photos');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = photo.path.contains('.') ? photo.path.split('.').last : 'jpg';
    final file = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}.$ext');
    await File(photo.path).copy(file.path);
    return file.path;
  }

  Future<void> _edit({Belonging? item}) async {
    final result = await showDialog<_FormResult>(
      context: context, barrierDismissible: false,
      builder: (_) => ItemDialog(picker: _picker, item: item));
    if (!mounted || result == null) return;
    String? path = item?.photo;
    if (result.removePhoto) path = null;
    if (result.photo != null) {
      try { path = await _copyPhoto(result.photo!); }
      catch (_) { _toast('Could not save that photo. Please try again.'); return; }
    }
    final updated = Belonging(
      id: item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: result.name, category: result.category, photo: path,
      created: item?.created ?? DateTime.now());
    setState(() {
      if (item == null) { _items.insert(0, updated); }
      else { final i = _items.indexWhere((x) => x.id == item.id); if (i >= 0) _items[i] = updated; }
    });
    await _save();
    if (mounted) _toast(item == null ? 'Saved ${updated.name}' : 'Updated ${updated.name}');
  }

  Future<void> _delete(Belonging item) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete this thing?'),
      content: Text('Remove "${item.name}" and its photo from this device?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.pop(c,true), child: const Text('Delete')),
      ]));
    if (yes != true) return;
    setState(() => _items.removeWhere((x) => x.id == item.id));
    await _save();
    if (item.photo != null) { try { await File(item.photo!).delete(); } catch (_) {} }
  }


  Future<void> _verifyAiModels() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Checking offline AI models…')),
        ]),
      ),
    );
    try {
      final details = await AiModelService().verifyInstalledModels();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('AI models are ready'),
          content: SingleChildScrollView(child: SelectableText(details)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('AI models not ready yet'),
          content: SelectableText(error.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  void _find(Belonging item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CameraFinderPage(item: item),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false, title: Row(children: [
      Container(width: 40,height: 40, decoration: BoxDecoration(color: green,borderRadius: BorderRadius.circular(13)),
        child: const Icon(Icons.center_focus_strong,color: Colors.white)),
      const SizedBox(width: 10),
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('FindMyThings',style: TextStyle(fontWeight: FontWeight.w800,color: green)),
        Text('Your things, easy to find.',style: TextStyle(fontSize: 11,color: muted)),
      ]),
    ])),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _tab == 2 ? _settings() : _inventory(),
    floatingActionButton: _tab == 2 ? null : FloatingActionButton.extended(
      onPressed: () => _edit(), backgroundColor: green, foregroundColor: Colors.white,
      icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add a thing')),
    bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() {_tab=v;_search='';}),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded),label:'My things'),
        NavigationDestination(icon: Icon(Icons.history_rounded),label:'Recent'),
        NavigationDestination(icon: Icon(Icons.settings_outlined),label:'Settings'),
      ]),
  );

  Widget _inventory() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(23)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR LITTLE INVENTORY', style: TextStyle(color: Color(0xFFC9D9CE), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text('${_items.length} ${_items.length == 1 ? 'thing' : 'things'} saved', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const Text('Saved privately on this device.', style: TextStyle(color: Color(0xFFE1EAE3), fontSize: 12)),
          ])),
          const Icon(Icons.inventory_2_outlined, size: 42, color: Color(0xFFE1EAE3)),
        ]),
      ),
      const SizedBox(height: 22),
      Text(_tab == 1 ? 'Recently added' : 'Your things', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF202A24))),
      const SizedBox(height: 12),
      TextField(onChanged: (value) => setState(() => _search = value), decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Icon(Icons.search))),
      const SizedBox(height: 16),
      if (_shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 42),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_a_photo_outlined, size: 55, color: green),
            const SizedBox(height: 14),
            Text(_search.isEmpty ? 'Nothing here yet' : 'No matches found', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_search.isEmpty ? 'Tap “Add a thing” to save your first belonging.' : 'Try another name.', textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          ]),
        )
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _shown.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.73),
          itemBuilder: (context, index) {
            final item = _shown[index];
            final hasPhoto = item.photo != null && File(item.photo!).existsSync();
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  if (hasPhoto) Image.file(File(item.photo!), fit: BoxFit.cover)
                  else Container(color: const Color(0xFFE8EEE8), child: const Icon(Icons.photo_outlined, size: 42, color: green)),
                  Positioned(right: 6, top: 6, child: Row(children: [
                    _Action(icon: Icons.edit_outlined, onTap: () => _edit(item: item)),
                    const SizedBox(width: 5),
                    _Action(icon: Icons.delete_outline, onTap: () => _delete(item)),
                  ])),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(10, 9, 10, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(item.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 7),
                  SizedBox(width: double.infinity, height: 34, child: FilledButton.tonalIcon(onPressed: () => _find(item), icon: const Icon(Icons.search, size: 16), label: const Text('Find it'), style: FilledButton.styleFrom(foregroundColor: green, backgroundColor: const Color(0xFFE8EEE8), padding: EdgeInsets.zero))),
                ])),
              ]),
            );
          },
        ),
    ],
  );
  Widget _settings() => ListView(padding:const EdgeInsets.all(22),children:[
    const Text('Settings',style:TextStyle(fontSize:27,fontWeight:FontWeight.w800)),
    const SizedBox(height:14),
    const _Setting(icon:Icons.wifi_off,title:'Works offline',subtitle:'Your saved belongings and photos stay on this device.'),
    const _Setting(icon:Icons.lock_outline,title:'Private by design',subtitle:'No account or cloud upload is used by this inventory.'),
    const _Setting(icon:Icons.photo_library_outlined,title:'Your photos',subtitle:'Reference photos are copied into the app’s private storage.'),
    const _Setting(icon:Icons.center_focus_strong,title:'Camera finder',subtitle:'Offline AI matching is the next feature to integrate.'),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: _verifyAiModels, icon: const Icon(Icons.memory), label: const Text('Check offline AI models')),
    Text('${_items.length} saved items',style:const TextStyle(color:muted)),
  ]);
}

class _Action extends StatelessWidget {
  const _Action({required this.icon,required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override Widget build(BuildContext context)=>Material(color:Colors.white.withValues(alpha:0.95),shape:const CircleBorder(),
    child:InkWell(customBorder:const CircleBorder(),onTap:onTap,child:Padding(padding:const EdgeInsets.all(8),child:Icon(icon,size:17,color:green))));
}

class _Setting extends StatelessWidget {
  const _Setting({required this.icon,required this.title,required this.subtitle});
  final IconData icon; final String title,subtitle;
  @override Widget build(BuildContext context)=>Card(color:Colors.white,elevation:0,margin:const EdgeInsets.only(bottom:10),
    child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xFFE8EEE8),foregroundColor:green,child:Icon(icon)),
      title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(subtitle)));
}

class _FormResult {
  const _FormResult({required this.name,required this.category,this.photo,this.removePhoto=false});
  final String name,category; final XFile? photo; final bool removePhoto;
}

class ItemDialog extends StatefulWidget {
  const ItemDialog({super.key,required this.picker,this.item});
  final ImagePicker picker; final Belonging? item;
  @override State<ItemDialog> createState()=>_ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late final TextEditingController _name,_category;
  XFile? _photo; bool _remove=false,_busy=false; String? _error;
  @override void initState(){super.initState();_name=TextEditingController(text:widget.item?.name??'');_category=TextEditingController(text:widget.item?.category??'My belongings');}
  @override void dispose(){_name.dispose();_category.dispose();super.dispose();}

  Future<void> _pick(ImageSource source) async {
    setState(()=>_busy=true);
    try { final p=await widget.picker.pickImage(source:source,imageQuality:88,maxWidth:1800); if(p!=null&&mounted)setState(()=>_photo=p); }
    catch(e){debugPrint('Picker error: $e');if(mounted)setState(()=>_error='Could not open photos. Check permissions and try again.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _photoMenu() async {
    final source=await showModalBottomSheet<ImageSource>(context:context,showDragHandle:true,backgroundColor:Colors.white,
      builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Padding(padding:EdgeInsets.all(12),child:Text('Add a photo',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),
        ListTile(leading:const Icon(Icons.photo_library_outlined),title:const Text('Choose from photos'),onTap:()=>Navigator.pop(c,ImageSource.gallery)),
        if(!Platform.isMacOS) ListTile(leading:const Icon(Icons.camera_alt_outlined),title:const Text('Take a photo'),onTap:()=>Navigator.pop(c,ImageSource.camera)),
        const SizedBox(height:12),
      ])));
    if(source!=null)await _pick(source);
  }

  void _submit(){
    final n=_name.text.trim();
    if(n.isEmpty){setState(()=>_error='Give your thing a name first.');return;}
    Navigator.pop(context,_FormResult(name:n,category:_category.text.trim().isEmpty?'My belongings':_category.text.trim(),photo:_photo,removePhoto:_remove));
  }

  @override Widget build(BuildContext context){
    final old=widget.item?.photo;
    final oldExists=old!=null&&File(old).existsSync()&&!_remove&&_photo==null;
    return AlertDialog(backgroundColor:const Color(0xFFFFFEFA),
      title:Text(widget.item==null?'Add a thing':'Edit your thing',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:_name,autofocus:true,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'What is it called?',hintText:'For example: Blue backpack')),
        const SizedBox(height:10),
        TextField(controller:_category,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Category',hintText:'For example: Everyday items')),
        const SizedBox(height:14),
        ClipRRect(borderRadius:BorderRadius.circular(14),child:SizedBox(height:140,width:double.infinity,
          child:_photo!=null?Image.file(File(_photo!.path),fit:BoxFit.cover):oldExists?Image.file(File(old),fit:BoxFit.cover):
            Container(color:const Color(0xFFE8EEE8),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Icon(Icons.add_a_photo_outlined,size:34,color:green),SizedBox(height:5),Text('A photo helps you recognise it',style:TextStyle(color:muted,fontSize:12)),
            ])))),
        const SizedBox(height:8),
        SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_busy?null:_photoMenu,icon:const Icon(Icons.photo_library_outlined),label:Text(_busy?'Opening…':(_photo!=null||oldExists)?'Change photo':'Add a photo'))),
        if(_photo!=null||oldExists)TextButton.icon(onPressed:()=>setState(()=>_remove=true),icon:const Icon(Icons.delete_outline),label:const Text('Remove photo')),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:7),child:Text(_error!,style:const TextStyle(color:Colors.red,fontSize:12))),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:_busy?null:_submit,child:const Text('Save')),
      ]);
  }
}


class CameraFinderPage extends StatefulWidget {
  const CameraFinderPage({super.key, required this.item});
  final Belonging item;

  @override
  State<CameraFinderPage> createState() => _CameraFinderPageState();
}

class _CameraFinderPageState extends State<CameraFinderPage> {
  CameraMacOSController? _cameraController;
  String? _cameraError;
  String _scanStatus = 'Starting automatic object scanning…';
  List<ObjectDetection> _detections = [];
  bool _processingFrame = false;
  bool _streamStarted = false;
  final AiModelService _ai = AiModelService();
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);
  int _inferenceCount = 0;
  String? _frameFilePath;
  double _cameraAspectRatio = 4 / 3;

  Future<void> _startAutomaticScanning(CameraMacOSController controller) async {
    if (_streamStarted) return;
    _streamStarted = true;
    try {
      await controller.startImageStream((CameraImageData? frame) {
        if (frame == null || !mounted || _processingFrame) return;
        if (frame.width > 0 && frame.height > 0) {
          _cameraAspectRatio = frame.width / frame.height;
        }
        final now = DateTime.now();
        if (now.difference(_lastInference).inMilliseconds < 2800) return;
        _lastInference = now;
        _processFrame(frame);
      });
      if (mounted) setState(() => _scanStatus = 'Scanning automatically…');
    } catch (error) {
      _streamStarted = false;
      if (mounted) setState(() => _scanStatus = 'Could not start live scanning: $error');
    }
  }

  Future<void> _processFrame(CameraImageData frame) async {
    _processingFrame = true;
    try {
      // Copy the camera buffer into transferable memory, then do pixel
      // conversion and JPEG encoding on a worker isolate.
      final encodedBytes = await compute<Map<String, Object>, Uint8List>(
        _encodeCameraFrame,
        <String, Object>{
          'bytes': TransferableTypedData.fromList([frame.bytes]),
          'width': frame.width,
          'height': frame.height,
          'bytesPerRow': frame.bytesPerRow,
        },
      );

      final directory = await getTemporaryDirectory();
      await directory.create(recursive: true);
      _frameFilePath ??= '${directory.path}/findmythings_live_frame.jpg';
      final imageFile = File(_frameFilePath!);
      await imageFile.writeAsBytes(encodedBytes, flush: false);

      var results = await _ai.detectObjects(imageFile.path);
      _inferenceCount++;
      final referencePath = widget.item.photo;
      // CLIP is deliberately less frequent than YOLO. It compares the
      // highest-confidence proposals only, while the preview stays live.
      if (results.isNotEmpty &&
          _inferenceCount % 4 == 0 &&
          referencePath != null &&
          await File(referencePath).exists()) {
        results = await _ai.matchDetectedRegions(
          referencePath: referencePath,
          framePath: imageFile.path,
          detections: results.take(1).toList(),
        );
      }

      // YOLO coordinates refer to the square letterboxed model input.
      // Convert them back to the original camera frame before painting.
      final scale = math.min(640 / frame.width, 640 / frame.height);
      final resizedWidth = frame.width * scale;
      final resizedHeight = frame.height * scale;
      final padX = (640 - resizedWidth) / 2;
      final padY = (640 - resizedHeight) / 2;
      final cameraDetections = results.map((d) {
        final left = (d.centerX * 640 - padX) / resizedWidth;
        final top = (d.centerY * 640 - padY) / resizedHeight;
        final boxWidth = d.width * 640 / resizedWidth;
        final boxHeight = d.height * 640 / resizedHeight;
        return ObjectDetection(
          label: d.label,
          confidence: d.confidence,
          centerX: left.clamp(0.0, 1.0).toDouble(),
          centerY: top.clamp(0.0, 1.0).toDouble(),
          width: boxWidth.clamp(0.0, 1.0).toDouble(),
          height: boxHeight.clamp(0.0, 1.0).toDouble(),
          similarity: d.similarity,
          isMatch: d.isMatch,
        );
      }).where((d) => d.width > 0.01 && d.height > 0.01).toList();

      if (!mounted) return;
      final matches = cameraDetections.where((d) => d.isMatch).length;
      setState(() {
        _detections = cameraDetections;
        _scanStatus = cameraDetections.isEmpty
            ? 'Scanning… no recognised objects in this frame.'
            : matches > 0
                ? '${widget.item.name} possible match found'
                : 'Scanning: ${cameraDetections.length} objects • comparing with saved ${widget.item.name}';
      });
    } catch (error) {
      if (mounted) setState(() => _scanStatus = 'Live detection error: $error');
    } finally {
      _processingFrame = false;
    }
  }

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null && _streamStarted) {
      controller.stopImageStream();
    }
    _ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101915),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101915),
        foregroundColor: Colors.white,
        title: const Text('Find your thing'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  if (widget.item.photo != null && File(widget.item.photo!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(widget.item.photo!), width: 54, height: 54, fit: BoxFit.cover),
                    )
                  else
                    const CircleAvatar(
                      radius: 27,
                      backgroundColor: Color(0xFFE8EEE8),
                      child: Icon(Icons.inventory_2_outlined, color: green),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Looking for', style: TextStyle(color: Color(0xFFB8C8BF), fontSize: 12)),
                        Text(widget.item.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: const Color(0xFF26372F), borderRadius: BorderRadius.circular(22)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraMacOSView(
                      fit: BoxFit.cover,
                      cameraMode: CameraMacOSMode.video,
                      onCameraInizialized: (controller) {
                        if (!mounted) return;
                        setState(() {
                          _cameraController = controller;
                          _cameraError = null;
                        });
                        _startAutomaticScanning(controller);
                      },
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: DetectionOverlayPainter(_detections, _cameraAspectRatio),
                      ),
                    ),
                    if (_cameraController == null && _cameraError == null)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 14),
                            Text('Starting your camera…', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    if (_cameraError != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_cameraError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.58), borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          _scanStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF81958A)), padding: const EdgeInsets.symmetric(vertical: 15)),
                  icon: const Icon(Icons.close),
                  label: const Text('Close camera'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter(this.detections, this.sourceAspectRatio);
  final List<ObjectDetection> detections;
  final double sourceAspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()..style = PaintingStyle.stroke..strokeWidth = 3;
    final marker = Paint();
    for (final detection in detections) {
      final color = detection.isMatch ? const Color(0xFF38E06F) : const Color(0xFFFF5252);
      border.color = color;
      marker.color = color;
      // Match the camera preview's BoxFit.cover crop exactly.
      final safeAspect = sourceAspectRatio > 0 ? sourceAspectRatio : 4 / 3;
      final scale = math.max(size.width / (safeAspect * 1000), size.height / 1000);
      final renderedWidth = safeAspect * 1000 * scale;
      final renderedHeight = 1000 * scale;
      final cropX = (renderedWidth - size.width) / 2;
      final cropY = (renderedHeight - size.height) / 2;
      final rect = Rect.fromCenter(
        center: Offset(
          detection.centerX * renderedWidth - cropX,
          detection.centerY * renderedHeight - cropY,
        ),
        width: detection.width * renderedWidth,
        height: detection.height * renderedHeight,
      ).intersect(Offset.zero & size);
      if (rect.width <= 0 || rect.height <= 0) continue;
      canvas.drawRect(rect, border);
      final triangle = Path()
        ..moveTo(rect.center.dx, rect.top - 12)
        ..lineTo(rect.center.dx - 8, rect.top - 26)
        ..lineTo(rect.center.dx + 8, rect.top - 26)
        ..close();
      canvas.drawPath(triangle, marker);
      final label = TextPainter(
        text: TextSpan(
          text: '${detection.label} ${(detection.confidence * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.6);
      final labelRect = Rect.fromLTWH(rect.left, (rect.top - label.height - 5).clamp(0, size.height), label.width + 10, label.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(labelRect, const Radius.circular(5)), marker);
      label.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections || oldDelegate.sourceAspectRatio != sourceAspectRatio;
}
