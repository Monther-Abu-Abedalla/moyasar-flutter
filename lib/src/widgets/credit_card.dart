import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';
import 'package:moyasar/src/utils/card_utils.dart';
import 'package:moyasar/src/utils/input_formatters.dart';
import 'package:moyasar/src/widgets/network_icons.dart';
import 'package:moyasar/src/widgets/three_d_s_webview.dart';

/// The widget that shows the Credit Card form and manages the 3DS step.
class CreditCard extends StatefulWidget {
  CreditCard(
      {super.key,
      required this.config,
      required this.onPaymentResult,
      this.locale = const Localization.en()})
      : textDirection = locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  final Function onPaymentResult;
  final PaymentConfig config;
  final Localization locale;
  final TextDirection textDirection;

  @override
  State<CreditCard> createState() => _CreditCardState();
}

class _CreditCardState extends State<CreditCard> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _cardData = CardFormModel();

  // Controllers for real-time updates
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvcController = TextEditingController();

  bool _isSubmitting = false;
  bool _tokenizeCard = false;
  bool _manualPayment = false;
  bool _showBack = false; // For card flip animation

  // Error state for each field
  String? _nameError;
  String? _cardNumberError;
  String? _expiryError;
  String? _cvcError;

  // Track if fields have been filled
  bool _nameFieldFilled = false;
  bool _cardNumberFieldFilled = false;
  bool _expiryFieldFilled = false;
  bool _cvcFieldFilled = false;

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    setState(() {
      _tokenizeCard = widget.config.creditCard?.saveCard ?? false;
      _manualPayment = widget.config.creditCard?.manual ?? false;
    });

    // Add listeners to controllers for real-time updates
    _nameController.addListener(_onControllerChanged);
    _cardNumberController.addListener(_onControllerChanged);
    _expiryController.addListener(_onControllerChanged);
    _cvcController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onControllerChanged);
    _cardNumberController.removeListener(_onControllerChanged);
    _expiryController.removeListener(_onControllerChanged);
    _cvcController.removeListener(_onControllerChanged);

    _nameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    super.dispose();
  }

  // Check if button should be enabled
  bool get _isButtonEnabled {
    bool allFieldsFilled =
        _nameFieldFilled && _cardNumberFieldFilled && _expiryFieldFilled && _cvcFieldFilled;

    bool noErrors =
        _nameError == null && _cardNumberError == null && _expiryError == null && _cvcError == null;

    return allFieldsFilled && noErrors && !_isSubmitting;
  }

  void _saveForm() async {
    if (!_isButtonEnabled) return;

    closeKeyboard();

    // Manually validate all fields
    _validateName(_nameController.text);
    _validateCardNumber(_cardNumberController.text);
    _validateExpiry(_expiryController.text);
    _validateCVC(_cvcController.text);

    // Check if all validations passed
    if (_nameError != null ||
        _cardNumberError != null ||
        _expiryError != null ||
        _cvcError != null) {
      return;
    }

    // Save the form data
    _cardData.name = _nameController.text;
    _cardData.number = CardUtils.getCleanedNumber(_cardNumberController.text);

    List<String> expireDate =
        CardUtils.getExpiryDate(_expiryController.text.replaceAll('\u200E', ''));
    _cardData.month = expireDate.first.replaceAll('\u200E', '');
    _cardData.year = expireDate[1].replaceAll('\u200E', '');
    _cardData.cvc = _cvcController.text;

    final source = CardPaymentRequestSource(
        creditCardData: _cardData, tokenizeCard: _tokenizeCard, manualPayment: _manualPayment);
    final paymentRequest = PaymentRequest(widget.config, source);

    setState(() => _isSubmitting = true);

    final result =
        await Moyasar.pay(apiKey: widget.config.publishableApiKey, paymentRequest: paymentRequest);

    setState(() => _isSubmitting = false);

    if (result is! PaymentResponse || result.status != PaymentStatus.initiated) {
      widget.onPaymentResult(result);
      return;
    }

    final String transactionUrl = (result.source as CardPaymentResponseSource).transactionUrl;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
            fullscreenDialog: true,
            maintainState: false,
            builder: (context) => ThreeDSWebView(
                transactionUrl: transactionUrl,
                on3dsDone: (String status, String message) async {
                  if (status == PaymentStatus.paid.name) {
                    result.status = PaymentStatus.paid;
                  } else if (status == PaymentStatus.authorized.name) {
                    result.status = PaymentStatus.authorized;
                  } else {
                    result.status = PaymentStatus.failed;
                    (result.source as CardPaymentResponseSource).message = message;
                  }
                  Navigator.pop(context);
                  widget.onPaymentResult(result);
                })),
      );
    }
  }

  // Validate name on change
  void _validateName(String? value) {
    setState(() {
      _nameError = CardUtils.validateName(value, widget.locale);
      _nameFieldFilled = value != null && value.trim().isNotEmpty;
    });
  }

  // Validate card number on change
  void _validateCardNumber(String? value) {
    setState(() {
      _cardNumberError = CardUtils.validateCardNum(value, widget.locale);
      _cardNumberFieldFilled = value != null && value.replaceAll(' ', '').length >= 13;
    });
  }

  // Validate expiry date on change
  void _validateExpiry(String? value) {
    setState(() {
      final cleanValue = value?.replaceAll('\u200E', '') ?? '';
      _expiryError = CardUtils.validateDate(cleanValue, widget.locale);
      _expiryFieldFilled = cleanValue.length >= 5;
    });
  }

  // Validate CVC on change
  void _validateCVC(String? value) {
    setState(() {
      _cvcError = CardUtils.validateCVC(value, widget.locale);
      _cvcFieldFilled = value != null && value.length >= 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      autovalidateMode: AutovalidateMode.disabled,
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            widget.locale.languageCode == 'ar' ? 'معلومات الدفع' : 'Payment Information',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 24),

          // Visual Credit Card
          _buildVisualCreditCard(),

          const SizedBox(height: 32),

          // Input Fields Below Card
          _buildInputFields(),

          const SizedBox(height: 24),

          // Pay Button
          _buildPayButton(),

          SaveCardNotice(tokenizeCard: _tokenizeCard, locale: widget.locale),
        ],
      ),
    );
  }

  Widget _buildVisualCreditCard() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showBack = !_showBack;
        });
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: _showBack ? _buildCardBack() : _buildCardFront(),
      ),
    );
  }

  Widget _buildCardFront() {
    return Container(
      key: const ValueKey('front'),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667eea),
            Color(0xFF764ba2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row with card type
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DEBIT',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Card Network Icon (Visa, Mastercard, etc.)
                _getCardNetworkIcon(),
              ],
            ),

            const Spacer(),

            // Card Number
            Text(
              _formatCardNumberForDisplay(_cardNumberController.text),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),

            const SizedBox(height: 16),

            // Bottom row with name and expiry
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.locale.languageCode == 'ar' ? 'اسم حامل البطاقة' : 'CARDHOLDER NAME',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nameController.text.isEmpty
                          ? 'YOUR NAME'
                          : _nameController.text.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.locale.languageCode == 'ar' ? 'تاريخ الانتهاء' : 'EXPIRES',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _expiryController.text.isEmpty ? 'MM/YY' : _expiryController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      key: const ValueKey('back'),
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667eea),
            Color(0xFF764ba2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Magnetic stripe
          Container(
            height: 40,
            color: Colors.black,
            width: double.infinity,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        'Signature',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _cvcController.text.isEmpty ? 'CVC' : _cvcController.text,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        // Name Field
        _buildStyledTextField(
          controller: _nameController,
          label: widget.locale.languageCode == 'ar' ? 'اسم حامل البطاقة' : widget.locale.nameOnCard,
          hint: widget.locale.languageCode == 'ar' ? 'اسم حامل البطاقة باللغة الانجليزية' : 'Enter cardholder name in English',
          onChanged: _validateName,
          onSaved: (value) {}, // Empty since we use controller
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z. ]')),
          ],
          keyboardType: TextInputType.text,
          error: _nameError,
        ),

        const SizedBox(height: 16),

        // Card Number Field
        _buildStyledTextField(
          controller: _cardNumberController,
          label: widget.locale.languageCode == 'ar' ? 'رقم البطاقة' : widget.locale.cardNumber,
          hint: '1234 5678 9012 3456',
          onChanged: _validateCardNumber,
          onSaved: (value) {}, // Empty since we use controller
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
            CardNumberInputFormatter(),
          ],
          error: _cardNumberError,
        ),

        const SizedBox(height: 16),

        // Expiry and CVC Row
        Row(
          children: [
            Expanded(
              child: _buildStyledTextField(
                controller: _expiryController,
                label: widget.locale.languageCode == 'ar' ? 'تاريخ الانتهاء' : widget.locale.expiry,
                hint: 'MM/YY',
                onChanged: _validateExpiry,
                onSaved: (value) {}, // Empty since we use controller
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  CardMonthInputFormatter(),
                ],
                error: _expiryError,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStyledTextField(
                controller: _cvcController,
                label: 'CVC',
                hint: '123',
                onChanged: _validateCVC,
                onSaved: (value) {}, // Empty since we use controller
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                error: _cvcError,
                onTap: () {
                  setState(() {
                    _showBack = true;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Function(String?) onChanged,
    required Function(String?) onSaved,
    List<TextInputFormatter>? inputFormatters,
    TextInputType keyboardType = TextInputType.number,
    String? error,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          error ?? label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: error != null ? Colors.red : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.next,
          inputFormatters: inputFormatters,
          onChanged: (value) {
            if (onChanged != null) {
              onChanged(value);
            }
          },
          onSaved: onSaved,
          onTap: onTap,
          validator: (value) {
            return null; // No inline validation
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? Colors.red : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? Colors.red : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? Colors.red : const Color(0xFF667eea),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2,
              ),
            ),
          ),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPayButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isButtonEnabled ? const Color(0xFF667eea) : Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isButtonEnabled ? 8 : 0,
          shadowColor: const Color(0xFF667eea).withOpacity(0.3),
        ),
        onPressed: _isButtonEnabled ? _saveForm : null,
        child: _isSubmitting
            ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.locale.languageCode == 'ar' ? 'ادفع ' : '${widget.locale.pay} ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    child: Image.asset(
                      'assets/images/saudiriyal.png',
                      color: Colors.white,
                      package: 'moyasar',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    getAmount(widget.config.amount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _formatCardNumberForDisplay(String cardNumber) {
    if (cardNumber.isEmpty) return '•••• •••• •••• ••••';

    String cleaned = cardNumber.replaceAll(' ', '');
    String formatted = '';

    for (int i = 0; i < 16; i += 4) {
      if (i < cleaned.length) {
        int end = (i + 4 < cleaned.length) ? i + 4 : cleaned.length;
        String group = cleaned.substring(i, end);

        // Pad with dots if group is incomplete
        while (group.length < 4) {
          group += '•';
        }

        formatted += group;
      } else {
        formatted += '••••';
      }

      if (i < 12) formatted += ' ';
    }

    return formatted;
  }

  Widget _getCardNetworkIcon() {
    String cardNumber = _cardNumberController.text.replaceAll(' ', '');

    if (cardNumber.startsWith('4')) {
      // Visa
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'VISA',
          style: TextStyle(
            color: Color(0xFF1A1F71),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    } else if (cardNumber.startsWith('5') || cardNumber.startsWith('2')) {
      // Mastercard
      return SizedBox(
        width: 40,
        height: 24,
        child: Stack(
          children: [
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFF79E1B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox(width: 40, height: 24);
  }
}

class SaveCardNotice extends StatelessWidget {
  const SaveCardNotice({super.key, required this.tokenizeCard, required this.locale});

  final bool tokenizeCard;
  final Localization locale;

  @override
  Widget build(BuildContext context) {
    return tokenizeCard
        ? Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info,
                  color: Color(0xFF667eea),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                ),
                Text(
                  locale.saveCardNotice,
                  style: const TextStyle(color: Color(0xFF667eea)),
                ),
              ],
            ))
        : const SizedBox.shrink();
  }
}

String showAmount(int amount, String currency, Localization locale) {
  final formattedAmount = (amount / 100).toStringAsFixed(2);
  return '${locale.pay} $currency $formattedAmount';
}

String getAmount(int amount) {
  final formattedAmount = (amount / 100).toStringAsFixed(2);
  return formattedAmount;
}

void closeKeyboard() => FocusManager.instance.primaryFocus?.unfocus();
