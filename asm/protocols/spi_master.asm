;=============================================================================
; Protocol: SPI Full-Duplex Master (Mode 0: CPOL=0, CPHA=0)
; Pins:
;   virt_out[0] : MOSI (Master Out Slave In)
;   side_out[0] : SCLK (SPI Serial Clock)
;   virt_in[0]  : MISO (Master In Slave Out)
;=============================================================================

init:
    SET SIDE, 0                     ; Ensure SCLK is low (CPOL=0)

entry:
    WAIT 1 TXF                      ; Wait until transmit data is available in TX FIFO
    PULL                            ; Fetch 8-bit transmit byte into OSR
    SET X, 7                        ; Loop counter for 8 SPI clock cycles

spi_bit:
    OUT PINS, 1       [1]           ; Shift MOSI bit onto pin, hold setup time
    SET SIDE, 1       [1]           ; Drive SCLK high (rising edge captures MISO)
    IN PIN0, 1                      ; Sample MISO bit into ISR
    SET SIDE, 0       [1]           ; Drive SCLK low (falling edge ends bit period)
    JMP X--, spi_bit                ; Loop until 8 bits exchanged

    PUSH                            ; Push received 8-bit byte from ISR to RX FIFO
    JMP entry                       ; Proceed to next byte transfer
