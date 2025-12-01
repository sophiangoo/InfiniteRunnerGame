module debouncer (
    input wire clk,
    input wire reset,
    input wire btn_in,
    output reg btn_out
);
    reg [19:0] counter;
    reg btn_sync_0, btn_sync_1;  // Synchronizer registers
    
    // Synchronize input to avoid metastability
    always @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end
    
    // Debounce logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            btn_out <= 0;
        end else begin
            if (btn_sync_1 != btn_out) begin
                counter <= counter + 1;
                if (counter >= 1_000_000) begin
                    btn_out <= btn_sync_1;
                    counter <= 0;
                end
            end else begin
                counter <= 0;
            end
        end
    end
endmodule

module clock_divider (
    input wire clk,  // 100 MHz master clock input 
    input wire reset,
    output reg clk_1Hz,     // 1 Hz for countdowns
    output reg clk_blink,   // 3 Hz for player blinking
    output reg clk_move,    // 1 Hz for obstacle movement
    output reg clk_display  // 1000 Hz for display multiplexing
);

    // counter sizes (count to these values, then toggle)
    parameter COUNT_1HZ = 100_000_000 / 2 - 1;
    parameter COUNT_BLINK = 100_000_000 / 6 - 1;
    parameter COUNT_MOVE = 100_000_000 / 2 - 1;
    parameter COUNT_DISPLAY = 100_000_000 / 2000 - 1;

    reg [26:0] counter_1Hz;
    reg [23:0] counter_blink;
    reg [26:0] counter_move;
    reg [15:0] counter_display;

    // 1 Hz clock for countdowns 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_1Hz <= 0;
            clk_1Hz <= 0;
        end else begin
            if (counter_1Hz >= COUNT_1HZ) begin
                counter_1Hz <= 0;
                clk_1Hz <= ~clk_1Hz;
            end else begin 
                counter_1Hz <= counter_1Hz + 1;
            end 
        end
    end
    
    // 3 Hz clock for player blinking 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_blink <= 0;
            clk_blink <= 0;
        end else begin
            if (counter_blink >= COUNT_BLINK) begin
                counter_blink <= 0;
                clk_blink <= ~clk_blink;
            end else begin
                counter_blink <= counter_blink + 1;
            end
        end
    end 

    // 1 Hz clock for obstacle movement 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_move <= 0;
            clk_move <= 0;
        end else begin
            if (counter_move >= COUNT_MOVE) begin
                counter_move <= 0;
                clk_move <= ~clk_move;
            end else begin
                counter_move <= counter_move + 1;
            end 
        end
    end

    // 1000 Hz clock for display 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_display <= 0;
            clk_display <= 0;
        end else begin
            if (counter_display >= COUNT_DISPLAY) begin
                counter_display <= 0;
                clk_display <= ~clk_display;
            end else begin
                counter_display <= counter_display + 1;
            end 
        end
    end
endmodule


module tick_generator (
    input wire clk, 
    input wire reset,
    input wire slow_clk,
    output reg tick
);

    reg slow_clk_prev;

    always @(posedge clk or posedge reset) begin 
        if (reset) begin
            slow_clk_prev <= 0;
            tick <= 0;
        end else begin
            slow_clk_prev <= slow_clk;
            tick <= slow_clk & ~slow_clk_prev; // Generate pulse on rising edge 
        end 
    end
endmodule


module lfsr (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire tick,
    output wire [1:0] random_out
);

    reg[7:0] lfsr_reg;
    wire feedback;

    // Feedback bit created by XOR-ing specific bits from current LFSR value
    assign feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            lfsr_reg <= 8'b10101010;     // Seed
        end else if (enable && tick) begin
            lfsr_reg <= {lfsr_reg[6:0], feedback};      // LFSR shifts left and feedback inserted at right end 
        end
    end

    // Use bottom 2 bits to map to lane 0, 1, or 2 (3 lanes) 
    assign random_out = (lfsr_reg[1:0] == 2'b11) ? 2'b00 : lfsr_reg[1:0];       // 3 invalid 
endmodule


// ------------ Player Controller Module --------
// Manages player position and movement 
module player_controller (
    input wire clk,
    input wire reset,
    input wire btn_left,
    input wire btn_right,
    input wire enable_gameplay,
    output reg [1:0] player_position
);
    wire btn_left_db, btn_right_db;
    reg btn_left_prev, btn_right_prev;
    wire btn_left_pulse, btn_right_pulse;
    
    // Debounce buttons
    debouncer db_left(
        .clk(clk),
        .reset(reset),
        .btn_in(btn_left),
        .btn_out(btn_left_db)
    );
    
    debouncer db_right(
        .clk(clk),
        .reset(reset),
        .btn_in(btn_right),
        .btn_out(btn_right_db)
    );
    
    // Edge detection for button presses
    always @(posedge clk) begin
        btn_left_prev <= btn_left_db;
        btn_right_prev <= btn_right_db;
    end
    
    assign btn_left_pulse = btn_left_db & ~btn_left_prev;
    assign btn_right_pulse = btn_right_db & ~btn_right_prev;
    
    // Update player position
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            player_position <= 2'b01;  // Start in middle lane
        end else if (enable_gameplay) begin
            if (btn_left_pulse && player_position > 0) begin
                player_position <= player_position - 1;     // Move left 
            end else if (btn_right_pulse && player_position < 2) begin
                player_position <= player_position + 1;     // Move right 
            end
        end
    end
endmodule


// ------------ Obstacle Generator Module --------
// Randomly generates obstacles 
module obstacle_generator(
    input wire clk,
    input wire reset,
    input wire enable_gameplay,
    input wire move_tick,
    output wire spawn_obstacle,
    output wire [1:0] new_obstacle_lane
);
    reg [3:0] spawn_counter;
    wire [1:0] random_lane;

    // LFSR for random generation
    lfsr rng(
        .clk(clk),
        .reset(reset),
        .enable(enable_gameplay),
        .tick(move_tick),
        .random_out(random_lane)
    );

    // Capture LFSR output into a register when a spawn occurs so lane used is stable & matched to the spawn pulse.
    reg [1:0] new_obstacle_lane_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            spawn_counter <= 0;
            new_obstacle_lane_reg <= 2'b00;
        end else if (enable_gameplay) begin
            if (move_tick) begin
                if (spawn_counter >= 1) begin
                    // On the spawn tick, capture the random lane into a register.
                    new_obstacle_lane_reg <= random_lane;
                    spawn_counter <= 0;
                end else begin
                    spawn_counter <= spawn_counter + 1;
                end
            end
        end else begin
            spawn_counter <= 0;
            new_obstacle_lane_reg <= 2'b00;
        end
    end
    
    assign spawn_obstacle = (enable_gameplay && move_tick && (spawn_counter >= 1));
    assign new_obstacle_lane = new_obstacle_lane_reg;

endmodule


// ------------ Obstacle Manager Module --------
// Tracks all active obstacles and their positions 
module obstacle_manager(
    input wire clk,
    input wire reset,
    input wire [1:0] new_obstacle_lane,
    input wire spawn_obstacle,
    input wire move_tick,
    // output reg [2:0] obstacle_array [3:0]  // [row][column]
    output reg [11:0] obstacle_array_flat  // Flat 12-bit output
);
    integer i;

    reg [2:0] obstacle_array [3:0]; // Internal 2D array 
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 4; i = i + 1) begin
                obstacle_array[i] <= 3'b000;
            end
        end else if (move_tick) begin
            // Shift obstacles DOWN (from higher index to lower index)
            // Top (digit 3) → Bottom (digit 0)
            obstacle_array[0] <= obstacle_array[1];  // Bottom gets from digit 1
            obstacle_array[1] <= obstacle_array[2];  // Digit 1 gets from digit 2
            obstacle_array[2] <= obstacle_array[3];  // Digit 2 gets from digit 3
            
            // Add new obstacle at top (digit 3)
            if (spawn_obstacle) begin
                obstacle_array[3] <= (3'b001 << new_obstacle_lane);
            end else begin
                obstacle_array[3] <= 3'b000;
            end
        end
    end

    // Flatten the 2D array into 1D output
    always @(*) begin
        obstacle_array_flat[2:0] = obstacle_array[0];  // Digit 0 (bottom)
        obstacle_array_flat[5:3] = obstacle_array[1];  // Digit 1
        obstacle_array_flat[8:6] = obstacle_array[2];  // Digit 2
        obstacle_array_flat[11:9] = obstacle_array[3];  // Digit 3 (top)
    end
endmodule


// ------------ Collision Detector Module --------
// Checks if player hits an obstacle 
module collision_detector (
    input wire clk,
    input wire reset,
    input wire [1:0] player_position,
    input wire [2:0] obstacle_array_bottom,
    input wire enable_gameplay,
    output reg collision_detected
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            collision_detected <= 0;
        end else if (enable_gameplay) begin
            // Check if obstacle is in player's lane
            collision_detected <= obstacle_array_bottom[player_position];
        end else begin
            collision_detected <= 0;
        end
    end
endmodule


// ------------ Score Counter Module --------
// Tracks player's score
module score_counter (
    input wire clk,
    input wire reset,
    input wire reset_score,
    input wire increment_score,
    input wire enable_gameplay,
    output reg [15:0] score  // 4 digits, 4 bits each
);
    always @(posedge clk or posedge reset) begin
        if (reset || reset_score) begin
            score <= 16'h0000;
        end else if (enable_gameplay && increment_score) begin
            if (score[3:0] == 4'd9) begin
                score[3:0] <= 4'd0;
                if (score[7:4] == 4'd9) begin
                    score[7:4] <= 4'd0;
                    if (score[11:8] == 4'd9) begin
                        score[11:8] <= 4'd0;
                        if (score[15:12] == 4'd9) begin
                            score[15:12] <= 4'd0;  // Overflow at 9999
                        end else begin
                            score[15:12] <= score[15:12] + 1;
                        end
                    end else begin
                        score[11:8] <= score[11:8] + 1;
                    end
                end else begin
                    score[7:4] <= score[7:4] + 1;
                end
            end else begin
                score[3:0] <= score[3:0] + 1;
            end
        end
    end
endmodule


// ------------ Game State Module --------
// Controls game modes 
module game_fsm(
    input wire clk,
    input wire reset,
    input wire btn_center,
    input wire collision_detected,
    input wire countdown_done,
    input wire lost_display_done,
    output reg [2:0] current_state,
    output reg enable_gameplay,
    output reg reset_score
);
    // State encoding
    parameter SCORE_MODE = 3'b000;
    parameter COUNTDOWN = 3'b001;
    parameter PLAY_MODE = 3'b010;
    parameter LOST = 3'b011;
    
    reg [2:0] next_state;
    wire btn_center_db;
    reg btn_center_prev;
    wire btn_center_pulse;
    
    // Debounce center button
    debouncer db_center(
        .clk(clk),
        .reset(reset),
        .btn_in(btn_center),
        .btn_out(btn_center_db)
    );
    
    // Edge detection
    always @(posedge clk) begin
        btn_center_prev <= btn_center_db;
    end
    assign btn_center_pulse = btn_center_db & ~btn_center_prev;
    
    // State register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= SCORE_MODE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always @(*) begin
        case (current_state)
            SCORE_MODE: begin
                if (btn_center_pulse)
                    next_state = COUNTDOWN;
                else
                    next_state = SCORE_MODE;
            end
            
            COUNTDOWN: begin
                if (countdown_done)
                    next_state = PLAY_MODE;
                else
                    next_state = COUNTDOWN;
            end
            
            PLAY_MODE: begin
                if (collision_detected)
                    next_state = LOST;
                else
                    next_state = PLAY_MODE;
            end
            
            LOST: begin
                if (lost_display_done)
                    next_state = SCORE_MODE;
                else
                    next_state = LOST;
            end
            
            default: next_state = SCORE_MODE;
        endcase
    end
    
    // Output logic
    always @(*) begin
        enable_gameplay = (current_state == PLAY_MODE);
        reset_score = (current_state == COUNTDOWN);
    end
endmodule


// ------------ Display Controller Module --------
module display_controller (
    input wire clk,
    input wire reset,
    input wire [2:0] current_state,
    input wire [15:0] score,
    input wire [1:0] player_position,
    input wire [11:0] obstacle_array_flat, // Flat 12-bit input 
    // input wire [2:0] obstacle_array [3:0],  // [row][column]
    input wire blink_tick,
    output reg [27:0] segments_out_flat
    // output reg [6:0] segments_out [3:0]     // {G, F, E, D, C, B, A}
);
    parameter SCORE_MODE = 3'b000;
    parameter COUNTDOWN = 3'b001;
    parameter PLAY_MODE = 3'b010;
    parameter LOST = 3'b011;
    
    reg player_visible;

    // Internal 2D array
    reg [6:0] segments_out [3:0];

    // Extract individual rows from flat array
    wire [2:0] obstacle_row0 = obstacle_array_flat[2:0];
    wire [2:0] obstacle_row1 = obstacle_array_flat[5:3];
    wire [2:0] obstacle_row2 = obstacle_array_flat[8:6];
    wire [2:0] obstacle_row3 = obstacle_array_flat[11:9];
    
    // Segment patterns for lanes 
    parameter [6:0] LANE_LEFT   = 7'b1110111;  // Segment D ON
    parameter [6:0] LANE_MIDDLE = 7'b0111111;  // Segment G ON
    parameter [6:0] BLANK       = 7'b1111111;  // All off
    parameter [6:0] LANE_RIGHT  = 7'b1111110;  // Segment A ON
    
    // Binary to 7-segment patterns 
    parameter [6:0] SEG_1 = 7'b1111001;
    parameter [6:0] SEG_0 = 7'b1000000;
    parameter [6:0] SEG_2 = 7'b0100100;
    parameter [6:0] SEG_3 = 7'b0110000;
    parameter [6:0] SEG_4 = 7'b0011001;
    parameter [6:0] SEG_5 = 7'b0010010;
    parameter [6:0] SEG_6 = 7'b0000010;
    parameter [6:0] SEG_7 = 7'b1111000;
    parameter [6:0] SEG_8 = 7'b0000000;
    parameter [6:0] SEG_9 = 7'b0010000;
    
    // Letters for "LOSS"
    parameter [6:0] SEG_L = 7'b1000111;
    parameter [6:0] SEG_O = 7'b1000000;
    parameter [6:0] SEG_S = 7'b0010010;
    parameter [6:0] SEG_T = 7'b0010010;
    
    // Player blinking
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            player_visible <= 1;
        end else if (blink_tick) begin
            player_visible <= ~player_visible;
        end
    end
    
    // Generate display data
    always @(*) begin
        case (current_state)
            SCORE_MODE: begin
                // Digit 3 (top) - Thousands
                case (score[15:12])
                    4'd0: segments_out[3] = SEG_0;
                    4'd1: segments_out[3] = SEG_1;
                    4'd2: segments_out[3] = SEG_2;
                    4'd3: segments_out[3] = SEG_3;
                    4'd4: segments_out[3] = SEG_4;
                    4'd5: segments_out[3] = SEG_5;
                    4'd6: segments_out[3] = SEG_6;
                    4'd7: segments_out[3] = SEG_7;
                    4'd8: segments_out[3] = SEG_8;
                    4'd9: segments_out[3] = SEG_9;
                    default: segments_out[3] = BLANK;
                endcase
                
                // Digit 2 - Hundreds
                case (score[11:8])
                    4'd0: segments_out[2] = SEG_0;
                    4'd1: segments_out[2] = SEG_1;
                    4'd2: segments_out[2] = SEG_2;
                    4'd3: segments_out[2] = SEG_3;
                    4'd4: segments_out[2] = SEG_4;
                    4'd5: segments_out[2] = SEG_5;
                    4'd6: segments_out[2] = SEG_6;
                    4'd7: segments_out[2] = SEG_7;
                    4'd8: segments_out[2] = SEG_8;
                    4'd9: segments_out[2] = SEG_9;
                    default: segments_out[2] = BLANK;
                endcase
                
                // Digit 1 - Tens
                case (score[7:4])
                    4'd0: segments_out[1] = SEG_0;
                    4'd1: segments_out[1] = SEG_1;
                    4'd2: segments_out[1] = SEG_2;
                    4'd3: segments_out[1] = SEG_3;
                    4'd4: segments_out[1] = SEG_4;
                    4'd5: segments_out[1] = SEG_5;
                    4'd6: segments_out[1] = SEG_6;
                    4'd7: segments_out[1] = SEG_7;
                    4'd8: segments_out[1] = SEG_8;
                    4'd9: segments_out[1] = SEG_9;
                    default: segments_out[1] = BLANK;
                endcase
                
                // Digit 0 (bottom) - Ones
                case (score[3:0])
                    4'd0: segments_out[0] = SEG_0;
                    4'd1: segments_out[0] = SEG_1;
                    4'd2: segments_out[0] = SEG_2;
                    4'd3: segments_out[0] = SEG_3;
                    4'd4: segments_out[0] = SEG_4;
                    4'd5: segments_out[0] = SEG_5;
                    4'd6: segments_out[0] = SEG_6;
                    4'd7: segments_out[0] = SEG_7;
                    4'd8: segments_out[0] = SEG_8;
                    4'd9: segments_out[0] = SEG_9;
                    default: segments_out[0] = BLANK;
                endcase
            end
            
            COUNTDOWN: begin
                // Blank during countdown
                segments_out[3] = BLANK;
                segments_out[2] = BLANK;
                segments_out[1] = BLANK;
                segments_out[0] = BLANK;
            end
            
            PLAY_MODE: begin
                // Digit 3 (TOP) - obstacles spawn here
                if (obstacle_row3[0])
                    segments_out[3] = LANE_LEFT;
                else if (obstacle_row3[1])
                    segments_out[3] = LANE_MIDDLE;
                else if (obstacle_row3[2])
                    segments_out[3] = LANE_RIGHT;
                else
                    segments_out[3] = BLANK;
                
                // Digit 2
                if (obstacle_row2[0])
                    segments_out[2] = LANE_LEFT;
                else if (obstacle_row2[1])
                    segments_out[2] = LANE_MIDDLE;
                else if (obstacle_row2[2])
                    segments_out[2] = LANE_RIGHT;
                else
                    segments_out[2] = BLANK;
                
                // Digit 1
                if (obstacle_row1[0])
                    segments_out[1] = LANE_LEFT;
                else if (obstacle_row1[1])
                    segments_out[1] = LANE_MIDDLE;
                else if (obstacle_row1[2])
                    segments_out[1] = LANE_RIGHT;
                else
                    segments_out[1] = BLANK;
                
                // Digit 0 (BOTTOM) - player position
                if (player_visible) begin
                    case (player_position)
                        2'b00: segments_out[0] = LANE_LEFT;
                        2'b01: segments_out[0] = LANE_MIDDLE;
                        2'b10: segments_out[0] = LANE_RIGHT;
                        default: segments_out[0] = BLANK;
                    endcase
                end else begin
                    segments_out[0] = BLANK;
                end
                
                // Show obstacle at bottom if present (collision moment)
                if (obstacle_row0[0])
                    segments_out[0] = segments_out[0] & LANE_LEFT;
                else if (obstacle_row0[1])
                    segments_out[0] = segments_out[0] & LANE_MIDDLE;
                else if (obstacle_row0[2])
                    segments_out[0] = segments_out[0] & LANE_RIGHT;
            end
            
            LOST: begin
                // Display "LOST"
                segments_out[3] = SEG_L;  
                segments_out[2] = SEG_O;  
                segments_out[1] = SEG_S;  
                segments_out[0] = SEG_T;  
            end
            
            default: begin
                segments_out[3] = BLANK;
                segments_out[2] = BLANK;
                segments_out[1] = BLANK;
                segments_out[0] = BLANK;
            end
        endcase
    end

    // Flatten the 2D array into 1D output
    always @(*) begin
        segments_out_flat[6:0] = segments_out[0];
        segments_out_flat[13:7] = segments_out[1];
        segments_out_flat[20:14] = segments_out[2];
        segments_out_flat[27:21] = segments_out[3];
    end

endmodule


// ------------ Display Mux Module --------
// Multiplexes the 4-digit 7-segment display 
module display_mux (
    input wire clk,
    input wire reset,
    input wire tick_display,
    input [27:0] segments_in_flat,
    // input wire [6:0] segments_in [3:0],
    output reg [6:0] segments_out,
    output reg [3:0] digit_enable
);
    reg [1:0] current_digit;

    // Extract individual digits from flat array
    wire [6:0] seg0 = segments_in_flat[6:0];
    wire [6:0] seg1 = segments_in_flat[13:7];
    wire [6:0] seg2 = segments_in_flat[20:14];
    wire [6:0] seg3 = segments_in_flat[27:21];
    
    // Cycle through digits on each tick
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_digit <= 0;
        end else if (tick_display) begin
            current_digit <= current_digit + 1;
        end
    end
    
    // Select active digit
    always @(*) begin
        case (current_digit)
            2'b00: begin
                digit_enable = 4'b1110;
                segments_out = seg0;
            end
            2'b01: begin
                digit_enable = 4'b1101;
                segments_out = seg1;
            end
            2'b10: begin
                digit_enable = 4'b1011;
                segments_out = seg2;
            end
            2'b11: begin
                digit_enable = 4'b0111;
                segments_out = seg3;
            end
        endcase
    end
endmodule


// ------------ Top Module --------
module game_top (
    input wire clk,          // 100MHz clock
    input wire reset,
    input wire btn_left,
    input wire btn_right,
    input wire btn_center,
    output wire [6:0] segments,
    output wire [3:0] digit_enable
);
    // Clock signals
    wire clk_1hz, clk_blink, clk_move, clk_display;
    wire tick_1hz, tick_move, tick_display;
    
    // Game state
    wire [2:0] current_state;
    wire enable_gameplay, reset_score;
    
    // Player
    wire [1:0] player_position;
    
    // Obstacles
    wire [1:0] new_obstacle_lane;
    wire spawn_obstacle;
    // wire [2:0] obstacle_array [3:0];

    // Flatten obstacle_array
    wire [11:0] obstacle_array_flat;

    // Extract individual rows 
    wire [2:0] obstacle_row0 = obstacle_array_flat[2:0];    // Digit 0 (bottom)
    wire [2:0] obstacle_row1 = obstacle_array_flat[5:3];    // Digit 1
    wire [2:0] obstacle_row2 = obstacle_array_flat[8:6];    // Digit 2
    wire [2:0] obstacle_row3 = obstacle_array_flat[11:9];   // Digit 3 (top)
    
    // Collision
    wire collision_detected;
    
    // Score
    wire [15:0] score;
    wire increment_score;
    
    // Display
    // wire [6:0] segments_array [3:0];

    // Flattened 1D array
    wire [27:0] segments_array_flat;  
    
    // Extract individual digits
    wire [6:0] seg0 = segments_array_flat[6:0];    // Digit 0
    wire [6:0] seg1 = segments_array_flat[13:7];   // Digit 1
    wire [6:0] seg2 = segments_array_flat[20:14];  // Digit 2
    wire [6:0] seg3 = segments_array_flat[27:21];  // Digit 3
    
    // Timing signals
    reg [1:0] countdown_counter;
    reg [2:0] lost_counter;
    wire countdown_done, lost_display_done;
    
    // Score increment logic - track previous bottom row
    reg [2:0] prev_obstacle_bottom;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_obstacle_bottom <= 3'b000;
        end else if (tick_move) begin
            // Store what's at bottom before the shift happens
            prev_obstacle_bottom <= obstacle_row0;
        end
    end

    // Increment score when obstacle passes bottom safely
    assign increment_score = tick_move && (prev_obstacle_bottom != 3'b000) && !collision_detected;

     // Countdown timer (3 seconds)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            countdown_counter <= 0;
        end else if (current_state == 3'b001 && tick_1hz) begin  // COUNTDOWN
            countdown_counter <= countdown_counter + 1;
        end else if (current_state != 3'b001) begin
            countdown_counter <= 0;
        end
    end
    assign countdown_done = (countdown_counter >= 3);
    
    // Lost display timer (5 seconds)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            lost_counter <= 0;
        end else if (current_state == 3'b011 && tick_1hz) begin  // LOST
            lost_counter <= lost_counter + 1;
        end else if (current_state != 3'b011) begin
            lost_counter <= 0;
        end
    end
    assign lost_display_done = (lost_counter >= 5);
    
    // Clock divider
    clock_divider clk_div(
        .clk(clk),
        .reset(reset),
        .clk_1Hz(clk_1hz),
        .clk_blink(clk_blink),
        .clk_move(clk_move),
        .clk_display(clk_display)
    );
    
    // Tick generators
    tick_generator tick_gen_1hz(
        .clk(clk),
        .reset(reset),
        .slow_clk(clk_1hz),
        .tick(tick_1hz)
    );
    
    tick_generator tick_gen_move(
        .clk(clk),
        .reset(reset),
        .slow_clk(clk_move),
        .tick(tick_move)
    );
    
    tick_generator tick_gen_display(
        .clk(clk),
        .reset(reset),
        .slow_clk(clk_display),
        .tick(tick_display)
    );

    // Game FSM
    game_fsm fsm(
        .clk(clk),
        .reset(reset),
        .btn_center(btn_center),
        .collision_detected(collision_detected),
        .countdown_done(countdown_done),
        .lost_display_done(lost_display_done),
        .current_state(current_state),
        .enable_gameplay(enable_gameplay),
        .reset_score(reset_score)
    );
    
    // Player controller
    player_controller player(
        .clk(clk),
        .reset(reset),
        .btn_left(btn_left),
        .btn_right(btn_right),
        .enable_gameplay(enable_gameplay),
        .player_position(player_position)
    );
    
    // Obstacle generator
    obstacle_generator obs_gen(
        .clk(clk),
        .reset(reset),
        .enable_gameplay(enable_gameplay),
        .move_tick(tick_move),
        .spawn_obstacle(spawn_obstacle),
        .new_obstacle_lane(new_obstacle_lane)
    );
    
    // Obstacle manager
    obstacle_manager obs_mgr(
        .clk(clk),
        .reset(reset),
        .new_obstacle_lane(new_obstacle_lane),
        .spawn_obstacle(spawn_obstacle),
        .move_tick(tick_move),
        .obstacle_array_flat(obstacle_array_flat)
    );
    
    // Collision detector
    collision_detector collision(
        .clk(clk),
        .reset(reset),
        .player_position(player_position),
        .obstacle_array_bottom(obstacle_row0),
        .enable_gameplay(enable_gameplay),
        .collision_detected(collision_detected)
    );
    
    // Score counter
    score_counter scorer (
        .clk(clk),
        .reset(reset),
        .reset_score(reset_score),
        .increment_score(increment_score),
        .enable_gameplay(enable_gameplay),
        .score(score)
    );
    
    // Display controller 
    display_controller disp_ctrl (
        .clk(clk),
        .reset(reset),
        .current_state(current_state),
        .score(score),
        .player_position(player_position),
        .obstacle_array_flat(obstacle_array_flat),
        .blink_tick(clk_blink),
        .segments_out_flat(segments_array_flat)
    );
    
    // Display multiplexer
    display_mux disp_mux(
        .clk(clk),
        .reset(reset),
        .tick_display(tick_display),
        .segments_in_flat(segments_array_flat),
        .segments_out(segments),
        .digit_enable(digit_enable)
    );
    
endmodule
