;=============================================================================
; Protocol: I2C Master Controller (Standard Mode / Fast Mode)
; Features: START & STOP condition generation, open-drain driving,
; 8-bit MSB-first transmission, ACK/NACK reception, and Clock Stretching wait.
; Pins:
;   virt_out[0] : SDA drive (1=release/float high, 0=pull low)
;   side_out[0] : SCL drive (1=release/float high, 0=pull low)
;   virt_in[0]  : SDA read
;   virt_in[1]  : SCL read (for slave clock-stretching detection)
;=============================================================================

init:
    SET SIDE, 1                     ; Release SCL high (idle)
    SET PINS, 1       [2]           ; Release SDA high (idle)

entry:
    WAIT 1 TXF                      ; Stall until host writes byte into TX FIFO
    PULL                            ; Fetch transmit byte into OSR
    SET PINS, 0       [2]           ; START condition: SDA pulled low while SCL is high
    SET SIDE, 0       [2]           ; Pull SCL low to begin bit transmission
    SET X, 7                        ; Loop counter for 8 data bits

i2c_bit:
    OUT PINS, 1       [2]           ; Shift bit to SDA while SCL is low
    SET SIDE, 1       [2]           ; Release SCL high
    WAIT 1 PIN1       [1]           ; Clock stretching: wait until slave releases SCL high
    SET SIDE, 0       [2]           ; Pull SCL low to end bit phase
    JMP X--, i2c_bit                ; Loop for all 8 bits

    ; 9th Cycle: ACK / NACK from slave
    SET PINS, 1       [2]           ; Release SDA high so slave can pull low to ACK
    SET SIDE, 1       [2]           ; Raise SCL for ACK sampling
    WAIT 1 PIN1       [1]           ; Clock stretching check
    IN PIN0, 1                      ; Sample ACK status bit (0=ACK, 1=NACK)
    SET SIDE, 0       [2]           ; Pull SCL low

    ; STOP Condition
    SET PINS, 0       [2]           ; Ensure SDA is low while SCL is low
    SET SIDE, 1       [2]           ; Release SCL high while SDA is still low
    SET PINS, 1       [4]           ; STOP condition: SDA released high while SCL is high

    PUSH                            ; Push ACK/NACK status to RX FIFO for host check
    JMP entry                       ; Ready for next transaction
