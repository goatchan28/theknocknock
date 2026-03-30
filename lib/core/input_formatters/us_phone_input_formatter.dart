import 'package:flutter/services.dart';

class UsPhoneInputFormatter extends TextInputFormatter {
  const UsPhoneInputFormatter();

  static String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static bool isValid(String value) {
    final digits = digitsOnly(value);
    return digits.length == 10 || (digits.length == 11 && digits.startsWith('1'));
  }

  static String normalizeForStorage(String value) {
    final digits = digitsOnly(value);
    if (digits.length == 10) {
      return '+1$digits';
    }
    if (digits.length == 11 && digits.startsWith('1')) {
      return '+$digits';
    }
    return digits;
  }

  static String formatForDisplay(String value) {
    final digits = digitsOnly(value);
    final tenDigits =
        digits.length == 11 && digits.startsWith('1') ? digits.substring(1) : digits;

    if (tenDigits.isEmpty) {
      return '';
    }
    if (tenDigits.length <= 3) {
      return tenDigits;
    }
    if (tenDigits.length <= 6) {
      final area = tenDigits.substring(0, 3);
      final rest = tenDigits.substring(3);
      return '($area) $rest';
    }
    final area = tenDigits.substring(0, 3);
    final prefix = tenDigits.substring(3, 6);
    final line = tenDigits.substring(6, tenDigits.length > 10 ? 10 : tenDigits.length);
    return '($area) $prefix-$line';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final capped =
        digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = formatForDisplay(capped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}
