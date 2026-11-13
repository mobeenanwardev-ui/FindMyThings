import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute;
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
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.light),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream, foregroundColor: Color(0xFF17231D),
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF17231D)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: Color(0xFF929B94), fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE8EAE4))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: green, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: green, foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      )),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white, elevation: 0, indicatorColor: const Color(0xFFE4EEE7),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    ),
    home: const HomePage(),
  );
}

class Belonging {
  const Belonging({required this.id, required this.name, required this.category, this.photo, this.photos = const [], required this.created});
  final String id, name, category;
  final String? photo;
  final List<String> photos;
  final DateTime created;
  List<String> get referencePhotos => photos.isNotEmpty ? photos : (photo == null ? const [] : [photo!]);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'category': category, 'photo': photo ?? (photos.isEmpty ? null : photos.first), 'photos': referencePhotos, 'created': created.toIso8601String()};
  factory Belonging.fromJson(Map<String, dynamic> j) {
    final savedPhotos = (j['photos'] as List?)?.whereType<String>().toList() ?? <String>[];
    final legacyPhoto = j['photo'] as String?;
    if (savedPhotos.isEmpty && legacyPhoto != null) savedPhotos.add(legacyPhoto);
    return Belonging(
      id: j['id'], name: j['name'], category: j['category'] ?? 'Other',
      photo: legacyPhoto ?? (savedPhotos.isEmpty ? null : savedPhotos.first),
      photos: savedPhotos,
      created: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now());
  }
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
    final savedPaths = result.removePhotos ? <String>[] : List<String>.from(item?.referencePhotos ?? const <String>[]);
    try {
      for (final photo in result.photos) { savedPaths.add(await _copyPhoto(photo)); }
    } catch (_) { _toast('Could not save those photos. Please try again.'); return; }
    final updated = Belonging(
      id: item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: result.name, category: result.category,
      photo: savedPaths.isEmpty ? null : savedPaths.first, photos: savedPaths,
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
    for (final path in item.referencePhotos) { try { await File(path).delete(); } catch (_) {} }
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
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF153F34), Color(0xFF286653)]),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: green.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR PERSONAL INVENTORY', style: TextStyle(color: Color(0xFFC9D9CE), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 10),
            Text('${_items.length} ${_items.length == 1 ? 'belonging' : 'belongings'} saved', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 5),
            const Text('Everything important, one tap away.', style: TextStyle(color: Color(0xFFE1EAE3), fontSize: 12)),
          ])),
          Container(width:58,height:58,decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.12),borderRadius:BorderRadius.circular(19)),
            child:const Icon(Icons.center_focus_strong_rounded,size:31,color:Color(0xFFE1EAE3))),
        ]),
      ),
      const SizedBox(height: 22),
      Text(_tab == 1 ? 'Recently added' : 'Your things', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Color(0xFF202A24))),
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
    const _Setting(icon:Icons.center_focus_strong,title:'Camera finder',subtitle:'Live object matching and visual tracking are enabled on the current macOS prototype.'),
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
  const _FormResult({required this.name,required this.category,this.photos=const [],this.removePhotos=false});
  final String name,category; final List<XFile> photos; final bool removePhotos;
}

class ItemDialog extends StatefulWidget {
  const ItemDialog({super.key,required this.picker,this.item});
  final ImagePicker picker; final Belonging? item;
  @override State<ItemDialog> createState()=>_ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late final TextEditingController _name,_category;
  final List<XFile> _newPhotos = [];
  bool _removeAll=false,_busy=false; String? _error;
  List<String> get _existingPhotos => _removeAll ? const [] : (widget.item?.referencePhotos ?? const []);
  @override void initState(){super.initState();_name=TextEditingController(text:widget.item?.name??'');_category=TextEditingController(text:widget.item?.category??'My belongings');}
  @override void dispose(){_name.dispose();_category.dispose();super.dispose();}

  Future<void> _pick() async {
    setState(()=>_busy=true);
    try {final picked=await widget.picker.pickMultiImage(imageQuality:88,maxWidth:1800);if(picked.isNotEmpty&&mounted)setState(()=>_newPhotos.addAll(picked));}
    catch(e){debugPrint('Picker error: $e');if(mounted)setState(()=>_error='Could not open photos. Check permissions and try again.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _photoMenu() async {
    final source=await showModalBottomSheet<ImageSource>(context:context,showDragHandle:true,backgroundColor:Colors.white,
      builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Padding(padding:EdgeInsets.all(12),child:Text('Add reference photos',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),
        ListTile(leading:const Icon(Icons.photo_library_outlined),title:const Text('Choose multiple photos'),onTap:()=>Navigator.pop(c,ImageSource.gallery)),
        if(!Platform.isMacOS) ListTile(leading:const Icon(Icons.camera_alt_outlined),title:const Text('Take a photo'),onTap:()=>Navigator.pop(c,ImageSource.camera)),
        const SizedBox(height:12),
      ])));
    if(source==ImageSource.gallery) await _pick();
    if(source==ImageSource.camera) {
      setState(()=>_busy=true);
      try {final p=await widget.picker.pickImage(source:ImageSource.camera,imageQuality:88,maxWidth:1800);if(p!=null&&mounted)setState(()=>_newPhotos.add(p));}
      catch(e){if(mounted)setState(()=>_error='Could not open camera. Check permissions and try again.');}
      finally{if(mounted)setState(()=>_busy=false);}
    }
  }

  void _submit(){
    final n=_name.text.trim();
    if(n.isEmpty){setState(()=>_error='Give your thing a name first.');return;}
    Navigator.pop(context,_FormResult(name:n,category:_category.text.trim().isEmpty?'My belongings':_category.text.trim(),photos:_newPhotos,removePhotos:_removeAll));
  }

  @override Widget build(BuildContext context){
    final existing=_existingPhotos.where((p)=>File(p).existsSync()).toList();
    final total=existing.length+_newPhotos.length;
    return AlertDialog(backgroundColor:const Color(0xFFFFFEFA),
      title:Text(widget.item==null?'Add a thing':'Edit your thing',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:_name,autofocus:true,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'What is it called?',hintText:'For example: Blue backpack')),
        const SizedBox(height:10),
        TextField(controller:_category,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Category',hintText:'For example: Everyday items')),
        const SizedBox(height:16),
        Row(children:[const Expanded(child:Text('Reference photos',style:TextStyle(fontWeight:FontWeight.w800))),Text('$total added',style:const TextStyle(color:muted,fontSize:12))]),
        const SizedBox(height:9),
        if(total==0) Container(height:112,width:double.infinity,decoration:BoxDecoration(color:const Color(0xFFE8EEE8),borderRadius:BorderRadius.circular(15)),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.photo_library_outlined,size:30,color:green),SizedBox(height:6),Text('Add a few angles for better matching',style:TextStyle(color:muted,fontSize:12))]))
        else SizedBox(height:104,child:ListView(scrollDirection:Axis.horizontal,children:[
          ...existing.map((p)=>Padding(padding:const EdgeInsets.only(right:8),child:ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.file(File(p),width:104,height:104,fit:BoxFit.cover)))),
          ..._newPhotos.map((p)=>Padding(padding:const EdgeInsets.only(right:8),child:ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.file(File(p.path),width:104,height:104,fit:BoxFit.cover)))),
        ])),
        const SizedBox(height:10),
        SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_busy?null:_photoMenu,icon:const Icon(Icons.add_photo_alternate_outlined),label:Text(_busy?'Opening…':'Add photos'))),
        if(total>0)TextButton.icon(onPressed:()=>setState(()=>_removeAll=true),icon:const Icon(Icons.delete_outline),label:const Text('Remove all reference photos')),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:7),child:Text(_error!,style:const TextStyle(color:Colors.red,fontSize:12))),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:_busy?null:_submit,child:const Text('Save'))]);
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
  Duration _lastDetectionDuration = Duration.zero;
  static const MethodChannel _trackerChannel = MethodChannel('com.findmythings/object_tracker');
  bool _trackingEnabled = false;
  int _trackingFrames = 0;
  static const int _framesBetweenRedetections = 24;
  List<ObjectDetection> _previousDetections = [];
  ObjectDetection? _lastConfirmedMatch;
  DateTime? _lastConfirmedMatchAt;
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
        // Vision tracking is lighter than YOLO, so sample it more often
        // for smoother marker motion. Keep detector passes at a safer cadence.
        final minimumInterval = _trackingEnabled ? 80 : 250;
        if (now.difference(_lastInference).inMilliseconds < minimumInterval) return;
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

      // Once CLIP confirms the requested belonging, Vision tracks its
      // bounding box on intervening camera frames. Periodic YOLO + CLIP
      // passes re-anchor the tracker to limit drift.
      if (_trackingEnabled && _trackingFrames < _framesBetweenRedetections) {
        try {
          final tracked = await _trackerChannel.invokeMapMethod<String, dynamic>(
            'trackFrame',
            <String, Object>{'image': encodedBytes},
          );
          if (tracked != null && tracked['tracked'] == true) {
            final confidence = (tracked['confidence'] as num?)?.toDouble() ?? 0.0;
            // Vision tracks the 640x640 letterboxed JPEG. Convert its box
            // back to camera-frame coordinates for the Flutter preview.
            final frameScale = math.min(640 / frame.width, 640 / frame.height);
            final frameWidth = frame.width * frameScale;
            final frameHeight = frame.height * frameScale;
            final framePadX = (640 - frameWidth) / 2;
            final framePadY = (640 - frameHeight) / 2;
            final trackedLeft = (tracked['x'] as num).toDouble();
            final trackedTop = (tracked['y'] as num).toDouble();
            final trackedWidth = (tracked['width'] as num).toDouble();
            final trackedHeight = (tracked['height'] as num).toDouble();
            final cameraLeft = (trackedLeft * 640 - framePadX) / frameWidth;
            final cameraTop = (trackedTop * 640 - framePadY) / frameHeight;
            final cameraWidth = trackedWidth * 640 / frameWidth;
            final cameraHeight = trackedHeight * 640 / frameHeight;
            final detection = ObjectDetection(
              label: widget.item.name,
              confidence: confidence,
              centerX: (cameraLeft + cameraWidth / 2).clamp(0.0, 1.0),
              centerY: (cameraTop + cameraHeight / 2).clamp(0.0, 1.0),
              width: cameraWidth.clamp(0.0, 1.0),
              height: cameraHeight.clamp(0.0, 1.0),
              isMatch: true,
            );
            _trackingFrames++;
            if (mounted) {
              setState(() {
                _detections = [detection];
                _scanStatus =
                    'Tracking ${widget.item.name} • Vision ${(confidence * 100).round()}%';
              });
            }
            return;
          }
        } on PlatformException catch (error) {
          debugPrint('Vision tracking error: ${error.message}');
        } on MissingPluginException {
          debugPrint('Native Vision tracker is not registered.');
        }
        _trackingEnabled = false;
        _trackingFrames = 0;
        _inferenceCount = 3; // Force CLIP to check the next detector result.
        _lastConfirmedMatch = null;
        _lastConfirmedMatchAt = null;
      } else if (_trackingEnabled) {
        // Run the detector again after a short tracking burst to correct drift.
        _trackingFrames = 0;
      }

      final detectionStartedAt = DateTime.now();
      var results = await _ai.detectObjects(imageFile.path);
      _lastDetectionDuration = DateTime.now().difference(detectionStartedAt);
      _inferenceCount++;
      final referencePaths = widget.item.referencePhotos;
      // CLIP is deliberately less frequent than YOLO. It compares the
      // highest-confidence proposals only, while the preview stays live.
      if (results.isNotEmpty &&
          (_trackingEnabled || _inferenceCount % 4 == 0) &&
          referencePaths.isNotEmpty &&
          referencePaths.any((path) => File(path).existsSync())) {
        final scored = await _ai.matchDetectedRegions(
          referencePaths: referencePaths,
          framePath: imageFile.path,
          detections: results.take(1).toList(),
        );
        // Keep the other YOLO boxes visible; CLIP only scores the best
        // proposal, it does not replace the complete detector result.
        if (scored.isNotEmpty) {
          results = [scored.first, ...results.skip(1)];
        }
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
      final stableDetections = _stabilizeDetections(cameraDetections, DateTime.now());
      final matchingDetections = stableDetections.where((d) => d.isMatch).toList();
      final confirmedMatch = matchingDetections.isEmpty ? null : matchingDetections.first;
      if (confirmedMatch != null && Platform.isMacOS) {
        try {
          // Convert camera-frame coordinates back into the square,
          // letterboxed JPEG coordinates consumed by Vision.
          final frameScale = math.min(640 / frame.width, 640 / frame.height);
          final frameWidth = frame.width * frameScale;
          final frameHeight = frame.height * frameScale;
          final framePadX = (640 - frameWidth) / 2;
          final framePadY = (640 - frameHeight) / 2;
          final squareCenterX =
              (confirmedMatch.centerX * frameWidth + framePadX) / 640;
          final squareCenterY =
              (confirmedMatch.centerY * frameHeight + framePadY) / 640;
          final squareWidth = confirmedMatch.width * frameWidth / 640;
          final squareHeight = confirmedMatch.height * frameHeight / 640;
          final boxLeft = (squareCenterX - squareWidth / 2).clamp(0.0, 1.0);
          final boxTop = (squareCenterY - squareHeight / 2).clamp(0.0, 1.0);
          final boxWidth = math.min(squareWidth, 1.0 - boxLeft).clamp(0.001, 1.0);
          final boxHeight = math.min(squareHeight, 1.0 - boxTop).clamp(0.001, 1.0);
          await _trackerChannel.invokeMethod<void>(
            'startTracking',
            <String, Object>{
              'image': encodedBytes,
              'x': boxLeft,
              'y': boxTop,
              'width': boxWidth,
              'height': boxHeight,
            },
          );
          _trackingEnabled = true;
          _trackingFrames = 0;
        } on PlatformException catch (error) {
          _trackingEnabled = false;
          debugPrint('Could not start Vision tracking: ${error.message}');
        } on MissingPluginException {
          _trackingEnabled = false;
          debugPrint('Native Vision tracker is not registered.');
        }
      } else if (_trackingEnabled) {
        // The periodic detector did not reconfirm the target. Stop trusting
        // the old track and let the next scheduled CLIP pass reacquire it.
        _trackingEnabled = false;
        _trackingFrames = 0;
        _lastConfirmedMatch = null;
        _lastConfirmedMatchAt = null;
      }
      final matches = stableDetections.where((d) => d.isMatch).length;
      setState(() {
        _detections = stableDetections;
        _scanStatus = stableDetections.isEmpty
            ? 'Scanning… no recognised objects in this frame.'
            : matches > 0
                ? '${widget.item.name} possible match found'
                : 'Scanning: ${stableDetections.length} objects • detection ${_lastDetectionDuration.inMilliseconds} ms';
      });
    } catch (error) {
      if (mounted) setState(() => _scanStatus = 'Live detection error: $error');
    } finally {
      _processingFrame = false;
    }
  }

  double _boxIoU(ObjectDetection a, ObjectDetection b) {
    final aLeft = a.centerX - a.width / 2;
    final aTop = a.centerY - a.height / 2;
    final aRight = a.centerX + a.width / 2;
    final aBottom = a.centerY + a.height / 2;
    final bLeft = b.centerX - b.width / 2;
    final bTop = b.centerY - b.height / 2;
    final bRight = b.centerX + b.width / 2;
    final bBottom = b.centerY + b.height / 2;
    final intersectionWidth = math.max(0.0, math.min(aRight, bRight) - math.max(aLeft, bLeft));
    final intersectionHeight = math.max(0.0, math.min(aBottom, bBottom) - math.max(aTop, bTop));
    final intersection = intersectionWidth * intersectionHeight;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  double _centerDistance(ObjectDetection a, ObjectDetection b) =>
      math.sqrt(math.pow(a.centerX - b.centerX, 2) + math.pow(a.centerY - b.centerY, 2));

  List<ObjectDetection> _stabilizeDetections(
    List<ObjectDetection> current,
    DateTime now,
  ) {
    const matchMemory = Duration(milliseconds: 2500);
    final smoothed = <ObjectDetection>[];

    for (final detection in current) {
      ObjectDetection? previous;
      var bestOverlap = 0.0;
      for (final candidate in _previousDetections) {
        if (candidate.label != detection.label) continue;
        final overlap = _boxIoU(candidate, detection);
        final distance = _centerDistance(candidate, detection);
        if (overlap > bestOverlap && (overlap > 0.04 || distance < 0.14)) {
          bestOverlap = overlap;
          previous = candidate;
        } else if (previous == null && distance < 0.14) {
          previous = candidate;
        }
      }

      // Exponential smoothing reduces box jitter without making the marker
      // feel too slow when the object moves.
      const newWeight = 0.68;
      final stable = previous == null
          ? detection
          : ObjectDetection(
              label: detection.label,
              confidence: detection.confidence,
              centerX: previous.centerX * (1 - newWeight) + detection.centerX * newWeight,
              centerY: previous.centerY * (1 - newWeight) + detection.centerY * newWeight,
              width: previous.width * (1 - newWeight) + detection.width * newWeight,
              height: previous.height * (1 - newWeight) + detection.height * newWeight,
              similarity: detection.similarity,
              isMatch: detection.isMatch,
            );
      smoothed.add(stable);
    }

    final freshMatch = smoothed.where((d) => d.isMatch).toList();
    if (freshMatch.isNotEmpty) {
      _lastConfirmedMatch = freshMatch.first;
      _lastConfirmedMatchAt = now;
    }

    final remembered = _lastConfirmedMatch;
    final confirmedAt = _lastConfirmedMatchAt;
    if (remembered != null &&
        confirmedAt != null &&
        now.difference(confirmedAt) <= matchMemory) {
      var bestIndex = -1;
      var bestScore = -1.0;
      for (var i = 0; i < smoothed.length; i++) {
        final candidate = smoothed[i];
        final overlap = _boxIoU(remembered, candidate);
        final distance = _centerDistance(remembered, candidate);
        final score = overlap + (1 - distance) * 0.01;
        if ((overlap > 0.025 || distance < 0.13) && score > bestScore) {
          bestIndex = i;
          bestScore = score;
        }
      }
      if (bestIndex >= 0) {
        final candidate = smoothed[bestIndex];
        smoothed[bestIndex] = ObjectDetection(
          label: candidate.label,
          confidence: candidate.confidence,
          centerX: candidate.centerX,
          centerY: candidate.centerY,
          width: candidate.width,
          height: candidate.height,
          similarity: candidate.similarity ?? remembered.similarity,
          isMatch: true,
        );
        _lastConfirmedMatch = smoothed[bestIndex];
      }
    } else if (confirmedAt != null && now.difference(confirmedAt) > matchMemory) {
      _lastConfirmedMatch = null;
      _lastConfirmedMatchAt = null;
    }

    _previousDetections = smoothed;
    return smoothed;
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
