import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

class ViewSavedFacesPage extends StatefulWidget {
  const ViewSavedFacesPage({Key? key}) : super(key: key);

  @override
  State<ViewSavedFacesPage> createState() => _ViewSavedFacesPageState();
}

class _ViewSavedFacesPageState extends State<ViewSavedFacesPage> {
  late Directory baseDir;
  List<Directory> persons = [];

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    baseDir = Directory('${(await getApplicationDocumentsDirectory()).path}/faces');
    if (!baseDir.existsSync()) baseDir.createSync(recursive: true);
    setState(() {
      persons = baseDir.listSync().whereType<Directory>().toList();
    });
  }

  Future<void> _deleteFolder(Directory dir) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xoá folder"),
        content: Text("Bạn có chắc muốn xoá '${dir.path.split('/').last}' không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xoá")),
        ],
      ),
    );

    if (confirm == true) {
      await dir.delete(recursive: true);
      _loadPersons();
    }
  }

  Future<void> _createFolder() async {
    String folderName = "";
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tạo folder mới"),
        content: TextField(
          autofocus: true,
          onChanged: (value) => folderName = value,
          decoration: const InputDecoration(hintText: "Tên folder..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(context, folderName), child: const Text("Tạo")),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newDir = Directory('${baseDir.path}/$result');
      if (!newDir.existsSync()) {
        newDir.createSync();
        _loadPersons();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("✅ Folder '$result' đã được tạo")));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("⚠ Folder '$result' đã tồn tại")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🖼 Danh sách người đã lưu"),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: _createFolder,
            tooltip: "Tạo folder mới",
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: persons.length,
        itemBuilder: (context, index) {
          final personDir = persons[index];
          final personName = personDir.path.split('/').last;
          return ListTile(
            title: Text(personName),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PersonImagesPage(personDir)),
            ),
            onLongPress: () => _deleteFolder(personDir),
          );
        },
      ),
    );
  }
}

class PersonImagesPage extends StatefulWidget {
  final Directory personDir;
  const PersonImagesPage(this.personDir, {Key? key}) : super(key: key);

  @override
  State<PersonImagesPage> createState() => _PersonImagesPageState();
}

class _PersonImagesPageState extends State<PersonImagesPage> {
  late List<File> files;

  @override
  void initState() {
    super.initState();
    files = widget.personDir.listSync().whereType<File>().toList();
  }

  Future<void> _deleteImage(File file) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xoá ảnh"),
        content: const Text("Bạn có chắc muốn xoá ảnh này không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xoá")),
        ],
      ),
    );

    if (confirm == true) {
      await file.delete();
      setState(() {
        files.remove(file);
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final newFile = File(pickedFile.path);
    final newPath = '${widget.personDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await newFile.copy(newPath);

    setState(() {
      files.add(File(newPath));
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("✅ Ảnh đã được tải lên folder")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.personDir.path.split('/').last),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: "Tải ảnh từ điện thoại",
            onPressed: _pickImageFromGallery,
          )
        ],
      ),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return GestureDetector(
            onLongPress: () => _deleteImage(file),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Image.file(File(file.path), fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}
