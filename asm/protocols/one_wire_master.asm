;=============================================================================
; Protocol: Dallas 1-Wire Master (Reset, Presence Detect, Bit R/W)
; Prescaler: 1 tick = 5 microseconds
; Pins: virt_out[0] drives DQ (open-drain: 0=drive low, 1=float high)
;       virt_in[0] reads DQ
;=============================================================================

reset_pulse:
    SET PINS, 0       [31]          ; Drive DQ low (part 1 of 480us reset pulse)
    NOP               [31]          ; Hold low
    NOP               [31]          ; Hold low
    SET PINS, 1       [14]          ; Release line high (float), wait 70us for presence
    IN PIN0, 1                      ; Sample presence pulse from slave (0=present, 1=missing)
    PUSH                            ; Send presence status to host
    NOP               [31]          ; Wait out remainder of presence period

entry:
    PULL                            ; Fetch next byte to transmit
    SET X, 7                        ; Loop 8 bits

write_bit:
    SET PINS, 0       [1]           ; Initiate time slot: pull DQ low for 10us
    OUT PINS, 1       [10]          ; Shift out bit (if 1: floats high; if 0: holds low)
    SET PINS, 1       [2]           ; Release high for recovery time (10us)
    JMP X--, write_bit              ; Loop 8 bits

    JMP entry                       ; Next byte
