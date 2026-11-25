;=============================================================================
; Protocol: SPI Slave Emulator
; Pins:
;   virt_in[0]  : SCLK from Master
;   virt_in[1]  : CS_N (Chip Select Active Low)
;   virt_in[2]  : MOSI
;   virt_out[0] : MISO
;=============================================================================

entry:
    WAIT 1 TXF                      ; Wait until transmit data is available in TX FIFO
    WAIT 0 PIN1                     ; Wait for CS_N to be asserted low
    PULL                            ; Fetch transmit byte into OSR
    SET X, 7                        ; Loop counter for 8 bits
    OUT PINS, 1                     ; Drive initial bit (Bit 7) onto MISO before SCLK rises

slave_bit:
    WAIT 1 PIN0                     ; Wait for SCLK rising edge
    IN PIN2, 1                      ; Sample MOSI bit into ISR
    WAIT 0 PIN0                     ; Wait for SCLK falling edge
    OUT PINS, 1                     ; Drive next MISO bit (Bits 6 down to 0)
    JMP X--, slave_bit              ; Loop for all 8 bits

    PUSH                            ; Push received byte into RX FIFO
    JMP entry                       ; Ready for next frame
