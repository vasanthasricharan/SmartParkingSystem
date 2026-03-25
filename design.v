// Module: smart_parking_system
// Description: Manages a 20-slot smart parking system.
// Enhanced with edge detection for inputs and display timers.
module smart_parking_system (
    // Inputs
    input wire           clk,
    input wire           rst_n,

    // Entry Gate Inputs
    input wire           car_at_entry_sensor,        // High when a car is at the entry gate
    input wire [1:0]     parking_duration_request,   // 01: <30m, 10: 30-60m, 11: >60m

    // Exit Gate Inputs
    input wire           car_at_exit_sensor,         // High when a car is at the exit gate
    input wire [15:0]    pin_entered_at_exit,        // PIN entered by the driver
    input wire           start_pin_check,            // Pulse to start checking the entered PIN

    // Outputs
    output reg           entry_gate_open,
    output reg           exit_gate_open,
    output reg           buzzer_on,

    // Display Outputs for Driver
    output reg [4:0]     assigned_slot_number,       // Displays the slot number to the entering driver
    output reg [15:0]    assigned_pin,               // Displays the PIN for the assigned slot
    output reg           display_full                // High if no slot is available in the requested category
);

//----------------------------------------------------------------
// Parameters
//----------------------------------------------------------------
localparam SLOT_COUNT             = 20;
localparam PIN_BASE               = 1000;
localparam PIN_WIDTH              = 16;
localparam SLOT_INDEX_WIDTH       = 5; // 2^5 = 32, enough for 20 slots

// Timer durations (in clock cycles). Adjust for your clock frequency.
// For a 50MHz clock, 50,000,000 cycles = 1 second.
// Using smaller values for faster simulation for this example.
localparam GATE_OPEN_DURATION     = 500;
localparam BUZZER_ON_DURATION     = 1000;
localparam DISPLAY_FULL_DURATION  = 2000; // Duration for 'display_full' to stay active

//----------------------------------------------------------------
// Internal Registers and Wires
//----------------------------------------------------------------

// State of each parking slot (1 = occupied, 0 = free)
reg [SLOT_COUNT-1:0] occupied_slots;

// Timers for gates, buzzer, and display
reg [31:0] entry_gate_timer;
reg [31:0] exit_gate_timer;
reg [31:0] buzzer_timer;
reg [31:0] display_full_timer;

// Edge detection registers (for one-shot event triggering)
reg car_at_entry_sensor_d0;
reg car_at_exit_sensor_d0;
reg start_pin_check_d0;

// Pulses generated on rising edge of the input signals
wire car_at_entry_pulse;
wire car_at_exit_pulse;
wire start_pin_check_pulse;


// --- Combinational Logic for finding slots and matching PINs ---
// These wires provide immediate results to the sequential block.
wire slot_found_for_entry;
wire [SLOT_INDEX_WIDTH-1:0] available_slot_index;

wire pin_match_found;
wire [SLOT_INDEX_WIDTH-1:0] slot_to_vacate_index;


//----------------------------------------------------------------
// Edge Detection Logic
//----------------------------------------------------------------
// These flip-flops create a one-clock-cycle delay for the inputs.
// The pulse signal will be high for one clock cycle when the input transitions from 0 to 1.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        car_at_entry_sensor_d0 <= 1'b0;
        car_at_exit_sensor_d0  <= 1'b0;
        start_pin_check_d0     <= 1'b0;
    end else begin
        car_at_entry_sensor_d0 <= car_at_entry_sensor;
        car_at_exit_sensor_d0  <= car_at_exit_sensor;
        start_pin_check_d0     <= start_pin_check;
    end
end

assign car_at_entry_pulse    = car_at_entry_sensor    && !car_at_entry_sensor_d0;
assign car_at_exit_pulse     = car_at_exit_sensor     && !car_at_exit_sensor_d0;
assign start_pin_check_pulse = start_pin_check        && !start_pin_check_d0;


//----------------------------------------------------------------
// Combinational Logic for Slot Searching (Entry)
//----------------------------------------------------------------
// 'slot_found_for_entry' checks if any slot is available in the requested category.
assign slot_found_for_entry =
    (parking_duration_request == 2'b01 && ~(&occupied_slots[4:0])) ||    // < 30m category (slots 0-4)
    (parking_duration_request == 2'b10 && ~(&occupied_slots[9:5])) ||    // 30-60m category (slots 5-9)
    (parking_duration_request == 2'b11 && ~(&occupied_slots[19:10])); // > 60m category (slots 10-19)

// Functions to find the first available slot index in each category.
// These are synthesizable priority encoders.
generate
    genvar i;
    // For slots 0-4
    function [SLOT_INDEX_WIDTH-1:0] find_slot_0_4;
        input [4:0] slots;
        integer j;
        begin
            find_slot_0_4 = 0; // Default; actual value found by loop
            for (j = 0; j < 5; j = j + 1)
                if (!slots[j]) begin
                    find_slot_0_4 = j;
                    break;
                end
        end
    endfunction

    // For slots 5-9
    function [SLOT_INDEX_WIDTH-1:0] find_slot_5_9;
        input [4:0] slots;
        integer j;
        begin
            find_slot_5_9 = 5; // Default; actual value found by loop
            for (j = 0; j < 5; j = j + 1)
                if (!slots[j]) begin
                    find_slot_5_9 = j + 5;
                    break;
                end
        end
    endfunction

    // For slots 10-19
    function [SLOT_INDEX_WIDTH-1:0] find_slot_10_19;
        input [9:0] slots; // Note: This function takes a 10-bit slice (occupied_slots[19:10])
        integer j;
        begin
            find_slot_10_19 = 10; // Default; actual value found by loop
            for (j = 0; j < 10; j = j + 1)
                if (!slots[j]) begin
                    find_slot_10_19 = j + 10;
                    break;
                end
        end
    endfunction

    // Assign the appropriate available slot based on the requested duration category.
    assign available_slot_index =
        (parking_duration_request == 2'b01) ? find_slot_0_4(occupied_slots[4:0]) :
        (parking_duration_request == 2'b10) ? find_slot_5_9(occupied_slots[9:5]) :
        (parking_duration_request == 2'b11) ? find_slot_10_19(occupied_slots[19:10]) :
        0; // Default if parking_duration_request is 2'b00 or other invalid value
endgenerate

//----------------------------------------------------------------
// Combinational Logic for PIN Matching (Exit)
//----------------------------------------------------------------
// This block continuously checks if the entered PIN matches any occupied slot.
reg pin_match_found_reg;
reg [SLOT_INDEX_WIDTH-1:0] slot_to_vacate_index_reg;
integer k;

always @(*) begin
    pin_match_found_reg = 1'b0;
    slot_to_vacate_index_reg = 0; // Default if no match
    for (k = 0; k < SLOT_COUNT; k = k + 1) begin
        // Check if slot is occupied AND the entered PIN matches the slot's expected PIN
        if (occupied_slots[k] && (pin_entered_at_exit == (PIN_BASE + k))) begin
            pin_match_found_reg      = 1'b1;
            slot_to_vacate_index_reg = k;
            break; // Found a match, no need to check further
        end
    end
end
assign pin_match_found    = pin_match_found_reg;
assign slot_to_vacate_index = slot_to_vacate_index_reg;

//----------------------------------------------------------------
// Main Sequential Logic (Clocked Process)
//----------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset all state registers to their initial safe values
        occupied_slots       <= 0;
        entry_gate_open      <= 1'b0;
        exit_gate_open       <= 1'b0;
        buzzer_on            <= 1'b0;
        entry_gate_timer     <= 0;
        exit_gate_timer      <= 0;
        buzzer_timer         <= 0;
        display_full_timer   <= 0;
        assigned_slot_number <= 0;
        assigned_pin         <= PIN_BASE; // Set to base PIN or another default (e.g., 16'hFFFF)
        display_full         <= 1'b0;
    end else begin

        // --- Timer Management ---
        // Decrement timers and turn off associated outputs when timers expire
        if (entry_gate_timer > 0) begin
            entry_gate_timer <= entry_gate_timer - 1;
        end else begin
            entry_gate_open <= 1'b0;
        end

        if (exit_gate_timer > 0) begin
            exit_gate_timer <= exit_gate_timer - 1;
        end else begin
            exit_gate_open <= 1'b0;
        end

        if (buzzer_timer > 0) begin
            buzzer_timer <= buzzer_timer - 1;
        end else begin
            buzzer_on <= 1'b0;
        end

        if (display_full_timer > 0) begin
            display_full_timer <= display_full_timer - 1;
        end else begin
            display_full <= 1'b0; // Turn off display_full when its timer expires
        end

        // --- Entry Gate Logic ---
        // Triggered by a rising edge of car_at_entry_sensor, a valid request,
        // and when the entry gate is not currently busy (timer is 0).
        if (car_at_entry_pulse && (parking_duration_request != 2'b00) && (entry_gate_timer == 0)) begin
            if (slot_found_for_entry) begin
                // A suitable slot was found in the requested category
                occupied_slots[available_slot_index] <= 1'b1; // Mark slot as occupied
                entry_gate_open      <= 1'b1;                  // Open the gate
                entry_gate_timer     <= GATE_OPEN_DURATION;    // Start gate timer

                // Update displays for the driver
                assigned_slot_number <= available_slot_index;
                assigned_pin         <= PIN_BASE + available_slot_index;
                // No need to set display_full to 0 here; its timer will handle it
            end else begin
                // No slots available in the requested category
                display_full         <= 1'b1;                     // Assert 'display_full'
                display_full_timer   <= DISPLAY_FULL_DURATION;    // Start its timer
                assigned_slot_number <= 0;                        // Clear display (or set to default)
                assigned_pin         <= PIN_BASE;                 // Clear PIN display
            end
        end

        // --- Exit Gate Logic ---
        // Triggered by a rising edge of car_at_exit_sensor AND start_pin_check,
        // and when the exit gate is not currently busy.
        if (car_at_exit_pulse && start_pin_check_pulse && (exit_gate_timer == 0)) begin
            if (pin_match_found) begin
                // Entered PIN is correct: free up the slot and open the gate
                occupied_slots[slot_to_vacate_index] <= 1'b0; // Mark slot as free
                exit_gate_open       <= 1'b1;                 // Open the gate
                exit_gate_timer      <= GATE_OPEN_DURATION;   // Start gate timer
                buzzer_on            <= 1'b0;               // Ensure buzzer is off
            end else begin
                // Entered PIN is incorrect: sound the buzzer
                buzzer_on    <= 1'b1;                    // Activate buzzer
                buzzer_timer <= BUZZER_ON_DURATION;      // Start buzzer timer
            end
        end
    end
end

endmodule