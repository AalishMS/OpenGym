import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class SpreadsheetImportService {
  final String baseUrl;

  SpreadsheetImportService({this.baseUrl = 'http://localhost:8000'});

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> convertFile(String filePath) async {
    final uri = Uri.parse('$baseUrl/convert');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw HttpException(
      'Server returned ${response.statusCode}: ${response.body}',
    );
  }
}
