import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

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

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  void _find(Belonging item) => showModalBottomSheet<void>(
    context: context, showDragHandle: true, backgroundColor: Colors.white,
    builder: (c) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ready to find it?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: green)),
        const SizedBox(height: 8),
        Text('You selected ${item.name}. Your reference photo is saved. The offline camera and AI matching engine still need to be connected.',
          style: const TextStyle(color: muted, height: 1.5)),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))),
      ]))));

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

  Widget _inventory() => CustomScrollView(slivers: [
    SliverPadding(padding: const EdgeInsets.fromLTRB(20,12,20,16), sliver: SliverList(delegate: SliverChildListDelegate([
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: green,borderRadius: BorderRadius.circular(23)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR LITTLE INVENTORY',style: TextStyle(color: Color(0xFFC9D9CE),fontSize:10,fontWeight:FontWeight.w800,letterSpacing:1.2)),
            const SizedBox(height:8),
            Text('${_items.length} ${_items.length == 1 ? 'thing' : 'things'} saved',style: const TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w800)),
            const Text('Saved privately on this device.',style:TextStyle(color:Color(0xFFE1EAE3),fontSize:12)),
          ])),
          const Icon(Icons.inventory_2_outlined,size:42,color:Color(0xFFE1EAE3)),
        ])),
      const SizedBox(height:22),
      Text(_tab == 1 ? 'Recently added' : 'Your things',style: const TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:Color(0xFF202A24))),
      const SizedBox(height:12),
      TextField(onChanged:(v)=>setState(()=>_search=v),decoration:const InputDecoration(hintText:'Search by name',prefixIcon:Icon(Icons.search))),
    ])))),
    if (_shown.isEmpty)
      SliverFillRemaining(hasScrollBody:false,child: Center(child: Padding(padding: const EdgeInsets.all(30),child: Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.add_a_photo_outlined,size:55,color:green),
        const SizedBox(height:14),
        Text(_search.isEmpty ? 'Nothing here yet' : 'No matches found',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)),
        const SizedBox(height:6),
        Text(_search.isEmpty ? 'Tap “Add a thing” to save your first belonging.' : 'Try another name.',textAlign:TextAlign.center,style:const TextStyle(color:muted)),
      ])))),
    if (_shown.isNotEmpty)
      SliverPadding(padding:const EdgeInsets.fromLTRB(20,0,20,110),sliver:SliverGrid(
        delegate:SliverChildBuilderDelegate((c,i){
          final item=_shown[i];
          final hasPhoto=item.photo!=null && File(item.photo!).existsSync();
          return Material(color:Colors.white,borderRadius:BorderRadius.circular(20),clipBehavior:Clip.antiAlias,
            child: Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:Stack(fit:StackFit.expand,children:[
                if(hasPhoto) Image.file(File(item.photo!),fit:BoxFit.cover)
                else Container(color:const Color(0xFFE8EEE8),child:const Icon(Icons.photo_outlined,size:42,color:green)),
                Positioned(right:6,top:6,child:Row(children:[
                  _Action(icon:Icons.edit_outlined,onTap:()=>_edit(item:item)),
                  const SizedBox(width:5),
                  _Action(icon:Icons.delete_outline,onTap:()=>_delete(item)),
                ])),
              ])),
              Padding(padding:const EdgeInsets.fromLTRB(10,9,10,10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(item.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:14)),
                Text(item.category,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:muted,fontSize:11)),
                const SizedBox(height:7),
                SizedBox(width:double.infinity,height:34,child:FilledButton.tonalIcon(
                  onPressed:()=>_find(item),icon:const Icon(Icons.search,size:16),label:const Text('Find it'),
                  style:FilledButton.styleFrom(foregroundColor:green,backgroundColor:const Color(0xFFE8EEE8),padding:EdgeInsets.zero))),
              ])),
            ]));
        },childCount:_shown.length),
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:0.73),
      )),
  ]);

  Widget _settings() => ListView(padding:const EdgeInsets.all(22),children:[
    const Text('Settings',style:TextStyle(fontSize:27,fontWeight:FontWeight.w800)),
    const SizedBox(height:14),
    const _Setting(icon:Icons.wifi_off,title:'Works offline',subtitle:'Your saved belongings and photos stay on this device.'),
    const _Setting(icon:Icons.lock_outline,title:'Private by design',subtitle:'No account or cloud upload is used by this inventory.'),
    const _Setting(icon:Icons.photo_library_outlined,title:'Your photos',subtitle:'Reference photos are copied into the app’s private storage.'),
    const _Setting(icon:Icons.center_focus_strong,title:'Camera finder',subtitle:'Offline AI matching is the next feature to integrate.'),
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
          child:_photo!=null?Image.file(File(_photo!.path),fit:BoxFit.cover):oldExists?Image.file(File(old!),fit:BoxFit.cover):
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
