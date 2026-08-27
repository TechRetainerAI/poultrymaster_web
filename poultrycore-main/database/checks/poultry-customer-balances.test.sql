DO $t$
DECLARE
    v_farm text := '3c4ac3cd-8792-4739-9b20-5f3b7d655a02';
    v_acct integer := 21;
    v_cust integer; s1 integer; s2 integer; s3 integer;
    v_group uuid; v_bal numeric; v_cash numeric; v_n integer; v_b boolean;
BEGIN
    v_cust := fnpoultrycustomer_resolve(v_farm, 'ZZ Test Store', 'tester');
    UPDATE customer SET paymenttermsdays = 0 WHERE customerid = v_cust;
    s1 := spsale_insert('tester', v_farm, (CURRENT_DATE - 40)::timestamp, 'Crate of eggs', 10, 50, 500, 'Cash', 'ZZ Test Store', NULL, 'sale one', false, NULL);
    s2 := spsale_insert('tester', v_farm, (CURRENT_DATE - 20)::timestamp, 'Crate of eggs', 16, 50, 800, 'Cash', 'ZZ Test Store', NULL, 'sale two', false, NULL);
    s3 := spsale_insert('tester', v_farm, (CURRENT_DATE - 5)::timestamp,  'Crate of eggs',  6, 50, 300, 'Cash', 'ZZ Test Store', NULL, 'sale three', false, NULL);
    UPDATE sale SET poultrycashaccountid = v_acct WHERE saleid IN (s1,s2,s3);
    PERFORM sppoultrypayment_record(v_farm, s1, 300, 'Cash', NULL, NULL, 'seed', 'tester');
    PERFORM sppoultrypayment_record(v_farm, s3, 50,  'Cash', NULL, NULL, 'seed', 'tester');

    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrycustomerbalances(v_farm, NULL, NULL, v_cust);
    RAISE NOTICE 'A. balance after seeding       expect 1250.00  got %', v_bal;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'B. cash from part payments     expect  350.00  got %', v_cash;
    SELECT count(*) INTO v_n FROM sppoultrycustomeropensales(v_farm, v_cust);
    RAISE NOTICE 'C. open sales                  expect       3  got %', v_n;

    v_group := sppoultrycustomerpayment_record(v_farm, v_cust, 700,
        jsonb_build_array(jsonb_build_object('saleid', s1, 'amount', 200),
                          jsonb_build_object('saleid', s2, 'amount', 500)),
        'Bank', NULL, v_acct, 'REF-001', 'bulk', 'CustomerBalances', 'tester');

    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrycustomerbalances(v_farm, NULL, NULL, v_cust);
    RAISE NOTICE 'D. balance after 700 bulk      expect  550.00  got %', v_bal;
    SELECT paid INTO v_b FROM sale WHERE saleid = s1;
    RAISE NOTICE 'E. sale one now fully paid     expect       t  got %', v_b;
    RAISE NOTICE 'F. sale two amountpaid         expect  500.00  got %', (SELECT amountpaid FROM sale WHERE saleid = s2);
    RAISE NOTICE 'G. sale three untouched        expect   50.00  got %', (SELECT amountpaid FROM sale WHERE saleid = s3);
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'H. cash 350+700                expect 1050.00  got %', v_cash;
    SELECT count(*) INTO v_n FROM sppoultrycustomerpayment_allocations(v_farm, v_group);
    RAISE NOTICE 'I. allocations in bulk payment expect       2  got %', v_n;
    SELECT count(*) INTO v_n FROM sppoultrycustomerpayment_history(v_farm, v_cust);
    RAISE NOTICE 'J. payment groups in history   expect       3  got %', v_n;
    SELECT count(*) INTO v_n FROM fnbalanceaudit(v_farm, 'poultry');
    RAISE NOTICE 'K. audit drift rows            expect       0  got %', v_n;
    SELECT count(*) INTO v_n FROM sppoultrycustomerstatement(v_farm, v_cust, NULL, NULL);
    RAISE NOTICE 'L. statement lines             expect gt   5  got %', v_n;
    SELECT runningbalance INTO v_bal FROM (
        SELECT runningbalance, row_number() OVER () AS rn
        FROM sppoultrycustomerstatement(v_farm, v_cust, NULL, NULL)) z
        ORDER BY rn DESC LIMIT 1;
    RAISE NOTICE 'M. statement closing balance   expect  550.00  got %', v_bal;
    SELECT count(*) INTO v_n FROM sppoultrycustomerstatement(v_farm, v_cust, (CURRENT_DATE - 10), NULL);
    RAISE NOTICE 'M2. windowed statement lines   expect gt   1  got %', v_n;
    SELECT debit INTO v_bal FROM sppoultrycustomerstatement(v_farm, v_cust, (CURRENT_DATE - 10), NULL) LIMIT 1;
    RAISE NOTICE 'M3. opening bal from 10d ago   expect  300.00  got %', v_bal;

    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_group, 'entered twice', 'tester');
    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrycustomerbalances(v_farm, NULL, NULL, v_cust);
    RAISE NOTICE 'N. balance after reversal      expect 1250.00  got %', v_bal;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'O. cash after reversal         expect  350.00  got %', v_cash;
    SELECT count(*) INTO v_n FROM fnbalanceaudit(v_farm, 'poultry');
    RAISE NOTICE 'P. audit drift after reversal  expect       0  got %', v_n;

    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 700,
            jsonb_build_array(jsonb_build_object('saleid', s1, 'amount', 200)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'Q. under-allocation            expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Q. under-allocation            expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 5000,
            jsonb_build_array(jsonb_build_object('saleid', s2, 'amount', 5000)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'R. over-allocate one sale      expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'R. over-allocate one sale      expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, 2147483600, 100,
            jsonb_build_array(jsonb_build_object('saleid', s2, 'amount', 100)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'S. unknown customer            expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'S. unknown customer            expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 200,
            jsonb_build_array(jsonb_build_object('saleid', 99999999, 'amount', 200)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'T. sale from another company   expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'T. sale from another company   expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_reverse(v_farm, v_group, 'again', 'tester');
        RAISE NOTICE 'U. double reversal             expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'U. double reversal             expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 400,
            jsonb_build_array(jsonb_build_object('saleid', s2, 'amount', 200),
                              jsonb_build_object('saleid', s2, 'amount', 200)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'V. same sale twice             expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'V. same sale twice             expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 100,
            jsonb_build_array(jsonb_build_object('saleid', s2, 'amount', 100)),
            'Bank', NULL, 2147483600, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'W. cash account another farm   expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'W. cash account another farm   expect   BLOCK  got BLOCK';
    END;
END
$t$;
