// Code your testbench here
// or browse Examples
`timescale 1ns/1ps

module tb_smart_parking;

    // Inputs to the DUT
    reg            clk;
    reg            rst_n;
    reg            car_at_entry_sensor;
    reg [1:0]      parking_duration_request;
    reg            car_at_exit_sensor;
    reg [15:0]     pin_entered_at_exit;
    reg            start_pin_check;

    // Outputs from the DUT
    wire           entry_gate_open;
    wire           exit_gate_open;
    wire           buzzer_on;
    wire [4:0]     assigned_slot_number;
    wire [15:0]    assigned_pin;
    wire           display_full;

    // Instantiate the Unit Under Test (UUT)
    smart_parking_system uut (
        .clk(clk),
        .rst_n(rst_n),
        .car_at_entry_sensor(car_at_entry_sensor),
        .parking_duration_request(parking_duration_request),
        .car_at_exit_sensor(car_at_exit_sensor),
        .pin_entered_at_exit(pin_entered_at_exit),
        .start_pin_check(start_pin_check),
        .entry_gate_open(entry_gate_open),
        .exit_gate_open(exit_gate_open),
        .buzzer_on(buzzer_on),
        .assigned_slot_number(assigned_slot_number),
        .assigned_pin(assigned_pin),
        .display_full(display_full)
    );

    // Clock generator: 10ns period (5ns high, 5ns low)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        // 1. Initial Reset
        $display("-------------------------------------------");
        $display("Time: %0t: Test Start: Resetting System", $time);
        rst_n = 0;
        car_at_entry_sensor = 0;
        parking_duration_request = 0;
        car_at_exit_sensor = 0;
        pin_entered_at_exit = 0;
        start_pin_check = 0;
        #20; // Hold reset for 2 clock cycles
        rst_n = 1;
        $display("Time: %0t: System out of reset.", $time);
        #20;

        // 2. SCENARIO 1: Car 1 arrives, wants <30 min slot.
        $display("-------------------------------------------");
        $display("Time: %0t: SCENARIO 1: Car 1 arrives, wants <30 min slot.", $time);
        car_at_entry_sensor = 1;
        parking_duration_request = 2'b01; // < 30 mins
        #10; // Allow combinational logic to settle (1 clock cycle)
        @(posedge clk); #1; // *CORRECTION:* Wait for outputs to register
        $display("Time: %0t: Slot %d (PIN: %d) assigned. Entry gate opens.", $time, assigned_slot_number, assigned_pin);
        wait (entry_gate_open == 0); // Wait until gate closes
        $display("Time: %0t: Entry gate closed.", $time);
        car_at_entry_sensor = 0; // De-assert sensor after entry
        parking_duration_request = 0;
        #100;

        // 3. SCENARIO 2: Car 2 arrives, wants >60 min slot.
        $display("-------------------------------------------");
        $display("Time: %0t: SCENARIO 2: Car 2 arrives, wants >60 min slot.", $time);
        car_at_entry_sensor = 1;
        parking_duration_request = 2'b11; // > 60 mins
        #10; // Allow combinational logic to settle (1 clock cycle)
        @(posedge clk); #1; // *CORRECTION:* Wait for outputs to register
        $display("Time: %0t: Slot %d (PIN: %d) assigned. Entry gate opens.", $time, assigned_slot_number, assigned_pin);
        wait (entry_gate_open == 0); // Wait until gate closes
        $display("Time: %0t: Entry gate closed.", $time);
        car_at_entry_sensor = 0; // De-assert sensor after entry
        parking_duration_request = 0;
        #100;

        // 4. SCENARIO 3: Car at exit enters WRONG PIN.
        $display("-------------------------------------------");
        $display("Time: %0t: SCENARIO 3: Car at exit enters WRONG PIN.", $time);
        car_at_exit_sensor = 1;
        pin_entered_at_exit = 1099; // Wrong PIN
        start_pin_check = 1;
        #10; // Allow combinational logic to settle (1 clock cycle)
        start_pin_check = 0; // De-assert start_pin_check pulse
        // No assigned_slot_number/pin here, so no extra wait needed for displays
        $display("Time: %0t: PIN check initiated. Buzzer should sound.", $time);
        wait (buzzer_on == 0); // Wait until buzzer turns off
        $display("Time: %0t: Buzzer has turned off.", $time);
        car_at_exit_sensor = 0;
        #100;

        // 5. SCENARIO 4: Car 1 at exit enters CORRECT PIN (1000).
        $display("-------------------------------------------");
        $display("Time: %0t: SCENARIO 4: Car 1 at exit enters CORRECT PIN (1000).", $time);
        car_at_exit_sensor = 1;
        pin_entered_at_exit = 1000; // Correct PIN for slot 0
        start_pin_check = 1;
        #10; // Allow combinational logic to settle (1 clock cycle)
        start_pin_check = 0; // De-assert start_pin_check pulse
        $display("Time: %0t: PIN check initiated. Exit gate should open.", $time);
        wait (exit_gate_open == 0); // Wait until gate closes
        $display("Time: %0t: Exit gate closed. Slot 0 should be free now.", $time);
        car_at_exit_sensor = 0;
        #100;
        
        // 6. SCENARIO 5: Car 3 arrives, wants <30 min slot. Should get the now-free slot 0.
        $display("-------------------------------------------");
        $display("Time: %0t: SCENARIO 5: Car 3 arrives, wants <30 min slot.", $time);
        car_at_entry_sensor = 1;
        parking_duration_request = 2'b01; // < 30 mins
        #10; // Allow combinational logic to settle (1 clock cycle)
        @(posedge clk); #1; // *CORRECTION:* Wait for outputs to register
        $display("Time: %0t: Slot %d (PIN: %d) assigned. Should be slot 0.", $time, assigned_slot_number, assigned_pin);
        wait (entry_gate_open == 0); // Wait until gate closes
        $display("Time: %0t: Entry gate closed.", $time);
        car_at_entry_sensor = 0; // De-assert sensor after entry
        parking_duration_request = 0;
        #100;
        
        $display("-------------------------------------------");
        $display("Time: %0t: Test Finished.", $time);
        $finish; // End simulation
    end

endmodule