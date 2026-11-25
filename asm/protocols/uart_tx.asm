;=============================================================================
; Protocol: UART 8N1 Transmitter (Cycle-Exact 4-Cycle Bit Period)
; Timing:
;   Start Bit : 4 cycles
;   Data Bits : 4 cycles per bit (OUT [2] + JMP = 4 cycles)
;   Stop Bit  : 4 cycles
; Features: Stalls on WAIT 1 TXF when idle to prevent spurious transmissions
;=============================================================================

init:
    SET PINS, 1                     ; Drive TX line high (idle mark)

entry:
    WAIT 1 TXF                     ; Stall until host pushes data into TX FIFO
    PULL                            ; Fetch 8-bit byte from TX FIFO into OSR
    SET PINS, 0       [2]           ; Assert START bit low (3 cycles)
    SET X, 7                        ; Loop counter (1 cycle -> Total 4 cycles for start bit)

bit_loop:
    OUT PINS, 1       [2]           ; Shift out 1 data bit (3 cycles)
    JMP X--, bit_loop               ; Loop for 8 bits (1 cycle -> Total 4 cycles per bit)

    SET PINS, 1       [3]           ; Assert STOP bit high for 4 cycles
    JMP entry                       ; Loop back for next byte
