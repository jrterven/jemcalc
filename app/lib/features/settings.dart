import 'package:flutter/material.dart';
import '../core/model.dart';

Future<void> showSettings(BuildContext context, AppModel model) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsPanel(model: model),
    );

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.model});
  final AppModel model;
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final url = TextEditingController(text: widget.model.baseUrl),
      token = TextEditingController(text: widget.model.token);
  late String language = widget.model.language,
      provider = widget.model.voiceProvider;
  late ThemeMode theme = widget.model.themeMode;
  bool checking = false, showToken = false;
  String? status;
  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> save({bool test = false}) async {
    setState(() => checking = true);
    try {
      await widget.model.configure(
        url: url.text.trim(),
        pilotToken: token.text,
        lang: language,
        theme: theme,
        provider: provider,
      );
      if (test) {
        final health = await widget.model.api.health();
        if (mounted) {
          setState(
            () => status =
                '✓ ${widget.model.s.t('Servidor disponible', 'Server available')} · ${health['status'] ?? 'ok'}',
          );
        }
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.model.s;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  s.t('Tu espacio de cálculo', 'Your math workspace'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: language,
              decoration: InputDecoration(labelText: s.t('Idioma', 'Language')),
              items: const [
                DropdownMenuItem(value: 'es', child: Text('Español')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) => setState(() => language = v!),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ThemeMode>(
              initialValue: theme,
              decoration: InputDecoration(
                labelText: s.t('Apariencia', 'Appearance'),
              ),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(s.t('Sistema', 'System')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(s.t('Claro', 'Light')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(s.t('Oscuro', 'Dark')),
                ),
              ],
              onChanged: (v) => setState(() => theme = v!),
            ),
            const SizedBox(height: 20),
            Text(
              s.t('SERVIDOR PRIVADO', 'PRIVATE SERVER'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: s.t('URL del servidor', 'Server URL'),
                hintText: 'https://192.168.1.10:8443',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: token,
              obscureText: !showToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: s.t('Token del piloto', 'Pilot token'),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => showToken = !showToken),
                  icon: Icon(
                    showToken
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: provider,
              decoration: InputDecoration(
                labelText: s.t('Transcripción de voz', 'Voice transcription'),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'scribe',
                  child: Text('Scribe v2 Realtime'),
                ),
                DropdownMenuItem(
                  value: 'openai',
                  child: Text('GPT Live Transcribe'),
                ),
              ],
              onChanged: (v) => setState(() => provider = v!),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  status!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: checking ? null : () => save(test: true),
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(s.t('Probar conexión', 'Test connection')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: checking ? null : save,
                  child: Text(s.t('Guardar', 'Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
