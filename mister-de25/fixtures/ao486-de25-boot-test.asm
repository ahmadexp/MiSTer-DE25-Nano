; Minimal 1.44 MB floppy boot sector for DE25-Nano ao486 hardware validation.
; It uses the loaded VGA BIOS to print a result, proving that CPU execution,
; system RAM, BIOS ROMs, the floppy path, and VGA interrupts are operational.

bits 16
org 0x7c00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti

    mov ax, 0x0003
    int 0x10
    mov si, message

.print:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0e
    mov bx, 0x000a
    int 0x10
    jmp .print

.done:
    sti
    hlt
    jmp .done

message db 'ao486 DE25-Nano booted successfully', 13, 10, 0

times 510-($-$$) db 0
dw 0xaa55
