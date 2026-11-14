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

  group('balances', () {
    test('Canara debit with balance', () {
      final b = SmsParser.parseBalance(
          'An amount of INR 2,000.00 has been DEBITED to your account XXX123 on 02/11/2026 towards UPI/DR/430512121212/ANIL KUMAR. Total Avail.bal INR 10,512.00. - Canara Bank')!;
      expect(b.account, '123');
      expect(b.balance, 10512.0);
      expect(b.delta, -2000.0);
    });
    test('credit with balance', () {
      final b = SmsParser.parseBalance(
          'Dear Customer, INR 15,000.00 credited to your A/c No XX1234 on 01-11-2026 by NEFT. Avl Bal: INR 60,210.50')!;
      expect(b.account, '1234');
      expect(b.balance, 60210.5);
      expect(b.delta, 15000.0);
    });
    test('HDFC debit without balance', () {
      final b = SmsParser.parseBalance(
          'Sent Rs.1,499.00\nFrom HDFC Bank A/C *1234\nTo BIGBASKET\nOn 01/11/26\nRef 430511112222\nNot You?')!;
      expect(b.account, '1234');
      expect(b.balance, isNull);
      expect(b.delta, -1499.0);
    });
  });

  test('card purchase OTP (code is not kept)', () {
    final o = SmsParser.parseCardOtp(
        '079003 is OTP for online purchase of Rs. 456.00 at SWIGGY FOOD thru State Bank Debit Card 9645. Do not share this OTP with anyone. -SBI')!;
    expect(o.amount, 456.0);
    expect(o.merchant, 'SWIGGY FOOD');
    expect(o.card, '9645');
    expect(o.toString().contains('079003'), isFalse);
    // Masked by the iPhone Shortcut
    final m = SmsParser.parseCardOtp(
        '****** is OTP for online purchase of Rs. 456.00 at SWIGGY FOOD thru State Bank Debit Card 9645.')!;
    expect(m.amount, 456.0);
    expect(SmsParser.parse('079003 is OTP for online purchase of Rs. 456.00 at SWIGGY FOOD'), isNull);
    expect(SmsParser.parseCardOtp('123456 is your OTP to log in to YONO'), isNull);
  });

  test('bank interest is flagged', () {
    final b = SmsParser.parseBalance(
        'INR 1,250.00 credited to A/c XX1234 on 31-10-26. Info: SB INT PD 01-07-26 TO 30-09-26. Avl bal INR 52,310')!;
    expect(b.isInterest, isTrue);
    expect(b.delta, 1250.0);
    final salary = SmsParser.parseBalance('INR 45,000.00 credited to your A/c XX1234 towards SALARY NOV. Avl Bal INR 99,000')!;
    expect(salary.isInterest, isFalse);
  });

  test('card numbers do not become bank accounts', () {
    final b = SmsParser.parseBalance('Rs.456.00 spent on your SBI Debit Card ending 9645 at SWIGGY. Avl Bal Rs.12,000.00');
    expect(b?.account == '9645', isFalse);
    final a = SmsParser.parseBalance('Rs 500 debited from A/c XX7475 on 14Nov. Avl Bal Rs 20,000')!;
    expect(a.account, '7475');
  });

  group("Hiba's SBI SMS", () {
    test('UPI debit without Rs', () {
      final p = SmsParser.parse('Dear UPI user A/C X7475 debited by 85 on date 04Jan26 trf to Indian Railways Refno 600430414658 If not u? call-1800111109 for other services-18001234-SBI')!;
      expect(p.amount, 85);
      expect(p.payee!.toLowerCase(), contains('indian railways'));
      expect(p.ref, '600430414658');
      final p2 = SmsParser.parse('Dear UPI user A/C X7475 debited by 50.00 on date 19Jan26 trf to KOCHI METRO RAIL Refno 601979838429 If not u? call-1800111109 for other services-18001234-SBI')!;
      expect(p2.amount, 50);
      expect(p2.payee!.toUpperCase(), contains('KOCHI METRO'));
      expect(SmsParser.parseBalance('Dear UPI user A/C X7475 debited by 85 on date 04Jan26 trf to Indian Railways Refno 600430414658 If not u?')!.account, '7475');
    });
    test('IMPS credit by mobile-linked account', () {
      const t = 'Dear Customer, Your a/c no. XXXXXXXX7475 is credited by Rs.4379.36 on 04-11-26 by a/c linked to mobile 0XXXXXX000-Swalhath K (IMPS Ref# 630825084285)-SBI';
      expect(SmsParser.parse(t), isNull);
      final b = SmsParser.parseBalance(t)!;
      expect(b.account, '7475');
      expect(b.delta, 4379.36);
      expect(b.payer, 'SWALHATH K');
      final b2 = SmsParser.parseBalance('Dear Customer, Your a/c no. XXXXXXXX7475 is credited by Rs.113440.00 on 14-03-26 by a/c linked to mobile 9XXXXXX810-WISDOM GOL (IMPS Ref# 607312490556)-SBI')!;
      expect(b2.delta, 113440);
      expect(b2.payer, 'WISDOM GOL');
    });
    test('NEFT salary credit', () {
      const t = 'Dear Customer, INR 20,538.00 credited to your A/c No XX7475 on 03/08/2026 through NEFT with UTR HDFCH01166734407 by VIVA COMPOSITE PANEL PVT LTD, INFO: BATCHID:00330001 NEFT DOMNEFT01 CX00000000TX1IER SALARY JULY 26-SBI';
      expect(SmsParser.parse(t), isNull);
      final b = SmsParser.parseBalance(t)!;
      expect(b.account, '7475');
      expect(b.delta, 20538);
      expect(b.payer, contains('VIVA COMPOSITE'));
      expect(b.isInterest, isFalse);
    });
  });
}
