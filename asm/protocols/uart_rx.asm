;=============================================================================
; Protocol: UART 8N1 Receiver (Cycle-Exact 4-Cycle Bit Sampling)
; Timing:
;   Mid-Eye Centering: 5.5 cycles from start edge
;   Bit Period: 4 cycles per bit (IN [2] + JMP = 4 cycles)
;=============================================================================

init:
    WAIT 1 PIN0                     ; Ensure line is idle high

entry:
    WAIT 0 PIN0                     ; Detect falling edge of START bit
    NOP               [1]           ; Delay 2 cycles
    NOP               [1]           ; Delay 2 cycles
    SET X, 7                        ; Delay 1 cycle (Total 5 cycles -> center of Bit 0)

bit_loop:
    IN PIN0, 1        [2]           ; Sample bit in center of bit cell (3 cycles)
    JMP X--, bit_loop               ; Loop for 8 data bits (1 cycle -> Total 4 cycles)

    PUSH                            ; Transfer assembled byte into RX FIFO
    WAIT 1 PIN0                     ; Wait for line to return high (STOP bit)
    JMP entry                       ; Ready for next incoming frame
