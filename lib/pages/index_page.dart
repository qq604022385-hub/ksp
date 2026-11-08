import 'package:flutter/material.dart';
import 'package:kazumi/pages/menu/menu.dart';

class IndexPage extends StatelessWidget {
  const IndexPage({super.key, required this.location});
  final String location;
  @override
  Widget build(BuildContext context) => ScaffoldMenu(location: location);
}
