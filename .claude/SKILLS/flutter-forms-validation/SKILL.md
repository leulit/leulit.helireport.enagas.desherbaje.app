---
name: flutter-forms-validation
description: >
  Flutter forms and validation skill — use this whenever the project involves
  forms, validation logic, dynamic fields, multi-step forms, or user data entry.
  Triggers on validation, form, TextFormField, input, submit, login form,
  registration. Always apply alongside flutter-core.
---

# Flutter Forms & Validation Skill

> Always apply **flutter-core** in parallel. This skill extends it with form-specific patterns.

## Key Principles

Forms use GetX architecture (see flutter-core). This skill adds **form-specific patterns**:
- **Reactive validation** — errors shown as user types (onChanged callbacks)
- **Validation composability** — combine validators
- **Multi-step flows** — step state management
- **Dynamic fields** — add/remove fields at runtime

---

## Reactive Validation & Validators

**Pattern**: Validators as pure functions (testable, no Flutter deps).

```dart
// core/utils/validators.dart
abstract class Validators {
  static String? required(String? value, {String field = 'This field'}) {
    return (value?.trim().isEmpty ?? true) ? '$field is required' : null;
  }

  static String? email(String? value) {
    if (value?.trim().isEmpty ?? true) return 'Email is required';
    return RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$').hasMatch(value!)
        ? null : 'Invalid email';
  }

  static String? minLength(String? value, int min, {String field = 'This field'}) {
    return (value?.length ?? 0) < min ? '$field ≥ $min chars' : null;
  }

  static String? phone(String? value) {
    if (value?.isEmpty ?? true) return null;
    return RegExp(r'^\+?[\d\s\-().]{7,15}$').hasMatch(value!)
        ? null : 'Invalid phone';
  }

  /// Compose validators — returns first error
  static String? compose(String? value, List<String? Function(String?)> validators) {
    for (final v in validators) {
      final err = v(value);
      if (err != null) return err;
    }
    return null;
  }
}
```

**Usage in controller**:
```dart
void onEmailChanged(String value) {
  emailError.value = Validators.compose(value, [
    (v) => Validators.required(v),
    (v) => Validators.email(v),
  ]) ?? '';
}
```

---

## Multi-Step Forms

```dart
class RegistrationController extends GetxController {
  final currentStep = 0.obs;
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  final nameError = ''.obs;
  final emailError = ''.obs;
  final isLoading = false.obs;

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        nameError.value = Validators.required(nameCtrl.text) ?? '';
        return nameError.value.isEmpty;
      case 1:
        emailError.value = Validators.email(emailCtrl.text) ?? '';
        return emailError.value.isEmpty;
      default:
        return true;
    }
  }

  void nextStep() {
    if (!_validateStep(currentStep.value)) return;
    if (currentStep.value < 2) {
      currentStep.value++;
    } else {
      submit();
    }
  }

  void previousStep() {
    if (currentStep.value > 0) currentStep.value--;
  }

  Future<void> submit() async { /* ... */ }

  @override
  void onClose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    super.onClose();
  }
}
```

---

## Dynamic Fields (add/remove at runtime)

```dart
class DynamicFormController extends GetxController {
  final fields = <FieldEntry>[].obs;

  void addField(String label) {
    fields.add(FieldEntry(
      id: DateTime.now().toString(),
      label: label,
      controller: TextEditingController(),
    ));
  }

  void removeField(String id) {
    fields.firstWhereOrNull((f) => f.id == id)?.controller.dispose();
    fields.removeWhere((f) => f.id == id);
  }

  @override
  void onClose() {
    for (final f in fields) f.controller.dispose();
    super.onClose();
  }
}

class FieldEntry {
  final String id, label;
  final TextEditingController controller;
  FieldEntry({required this.id, required this.label, required this.controller});
}
```
