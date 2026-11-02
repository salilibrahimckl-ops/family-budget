import 'package:family_budget/categorizer.dart';
import 'package:family_budget/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('debit SMS', () {
    final cases = <String, (double, String, String?)>{
      // Federal Bank
      'Rs 250.00 debited from your A/c XX1234 using UPI on 01-11-2026 10:15:22 to VPA swiggy@axisbank - (UPI Ref No 430512345678)-Federal Bank':
          (250, 'swiggy@axisbank', '430512345678'),
      // SBI
      'Dear UPI user A/C X1234 debited by 120.0 on date 01Nov26 trf to UBER INDIA Refno 430599990000. If not u? call 1800111109. -SBI':
          (120, 'UBER INDIA', '430599990000'),
      // HDFC (multi-line)
      'Sent Rs.1,499.00\nFrom HDFC Bank A/C *1234\nTo BIGBASKET\nOn 01/11/26\nRef 430511112222\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808':
          (1499, 'BIGBASKET', '430511112222'),
      // ICICI
      'ICICI Bank Acct XX123 debited for Rs 5000.00 on 05-Nov-26; RAJAN KURIES credited. UPI:430533334444. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.':
          (5000, 'RAJAN KURIES', '430533334444'),
      // Axis
      'INR 349.00 debited\nA/c no. XX1234\n01-11-26, 10:15:22\nUPI/P2M/430555556666/BOOKMYSHOW\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank':
          (349, 'BOOKMYSHOW', '430555556666'),
      // Kotak
      'Sent Rs.80.00 from Kotak Bank AC X1234 to chaikings@ybl on 01-11-26.UPI Ref 430577778888. Not you, https://kotak.com/KBANKT/Fraud':
          (80, 'chaikings@ybl', '430577778888'),
      // Canara
      'An amount of INR 2,000.00 has been DEBITED to your account XXX123 on 02/11/2026 towards UPI/DR/430512121212/ANIL KUMAR. Total Avail.bal INR 10,512.00. - Canara Bank':
          (2000, 'ANIL KUMAR', '430512121212'),
      // Federal Bank (paid to)
      'You have paid Rs.60.00 to MILMA PARLOUR via UPI on 01-11-26. UPI Ref: 430566667777 - Federal Bank':
          (60, 'MILMA PARLOUR', '430566667777'),
    };

    cases.forEach((sms, want) {
      test(sms.substring(0, 30), () {
        final p = SmsParser.parse(sms);
        expect(p, isNotNull);
        expect(p!.amount, want.$1);
        expect(p.payee.toLowerCase(), want.$2.toLowerCase());
        expect(p.ref, want.$3);
      });
    });
  });

  group('ignored SMS', () {
    for (final sms in [
      'Rs 5000.00 credited to your A/c XX1234 by UPI from RAHUL. Avl Bal Rs 12,000',
      '123456 is your OTP for UPI transaction of Rs 500. Do not share.',
      'Your A/c XX1234 will be debited Rs 999 on 05-Nov-26 for Netflix mandate.',
      'RAHUL has requested money of Rs 300 from you on Google Pay.',
      'UPI transaction of Rs 250 to SWIGGY failed. Amount if debited will be refunded.',
    ]) {
      test(sms.substring(0, 30), () => expect(SmsParser.parse(sms), isNull));
    }
  });

  test('dates', () {
    expect(SmsParser.parseDate('on 01Nov26 trf'), DateTime(2026, 11, 1, 12));
    expect(SmsParser.parseDate('On 01/11/26 Ref'), DateTime(2026, 11, 1, 12));
    expect(SmsParser.parseDate('on 05-Nov-26;'), DateTime(2026, 11, 5, 12));
  });

  test('categories', () {
    expect(Categorizer.guess('SWIGGY').category, 'food');
    expect(Categorizer.guess('UBER INDIA').category, 'travel');
    expect(Categorizer.guess('BIGBASKET').category, 'grocery');
    expect(Categorizer.guess('BOOKMYSHOW').category, 'fun');
    expect(Categorizer.guess('COCA COLA').category, isNot('travel'));
    expect(Categorizer.guess('RAJAN KURIES').chittiHint, isTrue);
    expect(Categorizer.guess('ANIL KUMAR').category, 'uncategorised');
  });
}
