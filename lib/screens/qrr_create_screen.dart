import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucasbeatsfederacao/providers/auth_provider.dart';
import 'package:lucasbeatsfederacao/models/qrr_model.dart';
import 'package:lucasbeatsfederacao/services/qrr_service.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';

class QRRCreateScreen extends StatefulWidget {
  const QRRCreateScreen({super.key});

  @override
  State<QRRCreateScreen> createState() => _QRRCreateScreenState();
}

class _QRRCreateScreenState extends State<QRRCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  final TextEditingController _maxParticipantsController = TextEditingController();
  final TextEditingController _requiredRolesController = TextEditingController();

  QRRType _selectedType = QRRType.mission;
  QRRPriority _selectedPriority = QRRPriority.medium;
  DateTime? _selectedStartTime;
  DateTime? _selectedEndTime;

  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _maxParticipantsController.dispose();
    _requiredRolesController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(BuildContext context, bool isStartTime) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (pickedTime != null) {
        setState(() {
          final selectedDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (isStartTime) {
            _selectedStartTime = selectedDateTime;
          } else {
            _selectedEndTime = selectedDateTime;
          }
        });
      }
    }
  }

  Future<void> _createQRR() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null || currentUser.clanId == null) { // Alterado para clanId
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Usuário não autenticado ou sem clã.')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        final qrrService = Provider.of<QRRService>(context, listen: false);
        final newQRR = {
          'title': _titleController.text,
          'description': _descriptionController.text,
          'imageUrl': _imageUrlController.text.isEmpty ? null : _imageUrlController.text,
          'clanId': currentUser.clanId!, // Alterado para clanId
          'type': _selectedType.toString().split('.').last,
          'priority': _selectedPriority.toString().split('.').last,
          'startTime': _selectedStartTime?.toIso8601String(),
          'endTime': _selectedEndTime?.toIso8601String(),
          'maxParticipants': _maxParticipantsController.text.isEmpty
              ? null
              : int.tryParse(_maxParticipantsController.text),
          'requiredRoles': _requiredRolesController.text.isEmpty
              ? []
              : _requiredRolesController.text.split(',').map((e) => e.trim()).toList(),
        };

        await qrrService.createQRR(newQRR);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QRR criada com sucesso!')), 
          );
          Navigator.pop(context);
        }
      } catch (e) {
        Logger.error('Erro ao criar QRR', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao criar QRR: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Nova Missão QRR'),
        backgroundColor: Colors.grey[900],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título da Missão',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira um título';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição da Missão',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, insira uma descrição';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'URL da Imagem (Opcional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16.0),
                    DropdownButtonFormField<QRRType>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Missão',
                        border: OutlineInputBorder(),
                      ),
                      items: QRRType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16.0),
                    DropdownButtonFormField<QRRPriority>(
                      value: _selectedPriority,
                      decoration: const InputDecoration(
                        labelText: 'Prioridade da Missão',
                        border: OutlineInputBorder(),
                      ),
                      items: QRRPriority.values.map((priority) {
                        return DropdownMenuItem(
                          value: priority,
                          child: Text(priority.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPriority = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16.0),
                    ListTile(
                      title: Text(
                        _selectedStartTime == null
                            ? 'Selecionar Data e Hora de Início'
                            : 'Início: ${_selectedStartTime!.day}/${_selectedStartTime!.month}/${_selectedStartTime!.year} ${_selectedStartTime!.hour}:${_selectedStartTime!.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDateTime(context, true),
                    ),
                    const SizedBox(height: 16.0),
                    ListTile(
                      title: Text(
                        _selectedEndTime == null
                            ? 'Selecionar Data e Hora de Término'
                            : 'Término: ${_selectedEndTime!.day}/${_selectedEndTime!.month}/${_selectedEndTime!.year} ${_selectedEndTime!.hour}:${_selectedEndTime!.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDateTime(context, false),
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _maxParticipantsController,
                      decoration: const InputDecoration(
                        labelText: 'Máximo de Participantes (Opcional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value != null && value.isNotEmpty && int.tryParse(value) == null) {
                          return 'Por favor, insira um número válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _requiredRolesController,
                      decoration: const InputDecoration(
                        labelText: 'Roles Necessários (separados por vírgula, Opcional)',
                        hintText: 'Ex: MEMBRO, LÍDER',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Center(
                      child: ElevatedButton(
                        onPressed: _createQRR,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Criar Missão QRR',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}


