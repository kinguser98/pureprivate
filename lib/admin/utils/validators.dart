class Validators {
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  static String? url(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final urlRegex = RegExp(r'^https?:\/\/.+\..+');
    if (!urlRegex.hasMatch(value.trim())) {
      return 'Please enter a valid URL';
    }
    return null;
  }

  static String? numeric(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
      return '$fieldName must be a number';
    }
    return null;
  }

  static String? minLength(String? value, int min, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (value.trim().length < min) {
      return '$fieldName must be at least $min characters';
    }
    return null;
  }

  static String? maxLength(String? value, int max, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > max) {
      return '$fieldName must not exceed $max characters';
    }
    return null;
  }
}
