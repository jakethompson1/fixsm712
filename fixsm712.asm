; revision g - try to be smarter about 640x480x16
; usage - run and then MODE CON COLS=80 to reset mode
; FIXSM712
; Copyright (C) 2016 Jacob Thompson <jakethompson1@gmail.com>
; All rights reserved.
;
; Redistribution and use in source and binary forms, with or without 
; modification, are permitted provided that the following conditions are met:
;
; 1. Redistributions of source code must retain the above copyright notice, 
; this list of conditions and the following disclaimer.
;
; 2. Redistributions in binary form must reproduce the above copyright notice, 
; this list of conditions and the following disclaimer in the documentation 
; and/or other materials provided with the distribution.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
; POSSIBILITY OF SUCH DAMAGE.

; Build with:
; yasm -o fixsm712.com fixsm712.asm

org 100h
bits 16
section .text
; it is critical that these two instructions occupy 4 bytes since we reuse
; the space to store the pointer to the old int 10h handler.
oldoff:
	jmp near start 
	nop
saved_ax:
	dw 0000h
saved_bx:
	dw 0000h
saved_dx:
	dw 0000h

;; int10h
; entry point for new int 10h interrupt handler that we install
int10h:
	pushf
	mov [cs:saved_ax], ax
	call far [cs:oldoff]
	; skip all of this if there was no change to video mode
	test word [cs:saved_ax], 0ff00h
	jnz nomode

	; save registers
	mov [cs:saved_bx], bx
	mov [cs:saved_dx], dx

	;; reconfigure the SM712 to output at real resolution
	; data sheet at:
	; https://www.usbid.com/assets/datasheets/A8/sm712g.pdf

	; unlock extended registers
	mov dx, 3c3h
	in al, dx
	and al, 1fh
	or al, 40h
	out dx, al

	;; disable LCD output
	; get old FPR31 value into al
	mov dx, 3c4h
	mov al, 31h
	out dx, al
	inc dx
	in al, dx
	; set to CRT only mode
	and al, 0f8h
	or al, 02h
	mov ah, al
	; write back ah to FPR31
	dec dx
	mov al, 31h
	out dx, al
	inc dx
	mov al, ah
	out dx, al

	;; switch to programmable clocking and disable dot clock/2
	; get old CCR68 value into ah
	dec dx
	mov al, 68h
	out dx, al
	inc dx
	in al, dx
	mov ah, al
	; set to programmable mode and ~CLK
	and ah, 0fh 
	or ah, 40h
	; write ah back to CCR68
	dec dx
	mov al, 68h
	out dx, al
	inc dx
	mov al, ah
	out dx, al


	;; set LCD size to 640x480
	; get old FPR30 value into al
	dec dx
	mov al, 30h
	out dx, al
	inc dx
	in al, dx
	; set size to 640x480
	and al, 0f3h
	mov ah, al
	; write ah back to FPR30
	mov al, 30h
	dec dx
	out dx, al
	inc dx
	mov al, ah
	out dx, al

	;; force dot clock to 28.325 MHz
	; TODO: set correctly according to mode
	dec dx
	mov bx, 5b97h
	cmp byte [cs:saved_ax], 12h
	jne textmode
	; change to 31.500 MHz if in 640x480x16 mode
	mov bx, 2c14h
textmode:
	mov al, 6ch
	out dx, al
	inc dx
	mov al, bh
	out dx, al
	dec dx
	mov al, 6dh
	out dx, al
	inc dx
	mov al, bl
	out dx, al

	;; disable vertical expansion
	; get old CRT9E value into al
	mov dx, 3d4h
	mov al, 9eh
	out dx, al
	inc dx
	in al, dx
	; mask away expansion bits
	and al, 0f8h
	mov ah, al
	; write back ah to CRT9E
	dec dx
	mov al, 9eh
	out dx, al
	inc dx
	mov al, ah
	out dx, al

	;; read and write back VGA regs to update shadow regs
	; CRT registers 00h-07h, 09h, 10h-12h, 15h-16h
	;  al - temp
	;  ah - register being written back
	;  bl - temp
	;  dx - base
	xor ah, ah
writeback:
	dec dx
	; read old value from index ah into bl
	mov al, ah
	out dx, al
	inc dx
	in al, dx
	mov bl, al
	; write back value in bl to index ah
	mov al, ah
	dec dx
	out dx, al
	mov al, bl
	inc dx
	out dx, al

	inc ah
	; skip 08h, 0ah-0fh, 13h-14h
	cmp ah, 08h
	jne skip08
	inc ah
skip08:
	cmp ah, 0ah
	jne skip0a
	add ah, 06h
skip0a:
	cmp ah, 13h
	jne skip13
	add ah, 02h
skip13:
	cmp ah, 17h
	jne writeback

	mov ax, [cs:saved_ax]
	mov bx, [cs:saved_bx]
	mov dx, [cs:saved_dx]
nomode:
	iret

;; start
; entry point when run from the command line
start:
	; command line args? - then print license
	cmp byte [80h], 00h
	jnz license

	; get old int10h vector in es:bx
	mov ax, 3510h
	int 21h
	mov [oldoff], bx
	mov [oldoff+2], es

	; free environment segment
	mov es, [002ch]
	mov ah, 49h
	int 21h

	; set new int10h vector from ds:dx
	push cs
	pop ds
	mov dx, int10h
	mov ax, 2510h
	int 21h

	; TSR
	mov dx, start
	int 27h

license:
	mov dx, msg
	mov ah, 09h
	int 21h

	mov ax, 4c00h
	int 21h

msg:
	db 70
	db 73
	db 88
	db 83
	db 77
	db 55
	db 49
	db 50
	db 13
	db 10
	db 67
	db 111
	db 112
	db 121
	db 114
	db 105
	db 103
	db 104
	db 116
	db 32
	db 40
	db 67
	db 41
	db 32
	db 50
	db 48
	db 49
	db 54
	db 32
	db 74
	db 97
	db 99
	db 111
	db 98
	db 32
	db 84
	db 104
	db 111
	db 109
	db 112
	db 115
	db 111
	db 110
	db 32
	db 60
	db 106
	db 97
	db 107
	db 101
	db 116
	db 104
	db 111
	db 109
	db 112
	db 115
	db 111
	db 110
	db 49
	db 64
	db 103
	db 109
	db 97
	db 105
	db 108
	db 46
	db 99
	db 111
	db 109
	db 62
	db 13
	db 10
	db 65
	db 108
	db 108
	db 32
	db 114
	db 105
	db 103
	db 104
	db 116
	db 115
	db 32
	db 114
	db 101
	db 115
	db 101
	db 114
	db 118
	db 101
	db 100
	db 46
	db 13
	db 10
	db 13
	db 10
	db 82
	db 101
	db 100
	db 105
	db 115
	db 116
	db 114
	db 105
	db 98
	db 117
	db 116
	db 105
	db 111
	db 110
	db 32
	db 97
	db 110
	db 100
	db 32
	db 117
	db 115
	db 101
	db 32
	db 105
	db 110
	db 32
	db 115
	db 111
	db 117
	db 114
	db 99
	db 101
	db 32
	db 97
	db 110
	db 100
	db 32
	db 98
	db 105
	db 110
	db 97
	db 114
	db 121
	db 32
	db 102
	db 111
	db 114
	db 109
	db 115
	db 44
	db 32
	db 119
	db 105
	db 116
	db 104
	db 32
	db 111
	db 114
	db 32
	db 119
	db 105
	db 116
	db 104
	db 111
	db 117
	db 116
	db 13
	db 10
	db 109
	db 111
	db 100
	db 105
	db 102
	db 105
	db 99
	db 97
	db 116
	db 105
	db 111
	db 110
	db 44
	db 32
	db 97
	db 114
	db 101
	db 32
	db 112
	db 101
	db 114
	db 109
	db 105
	db 116
	db 116
	db 101
	db 100
	db 32
	db 112
	db 114
	db 111
	db 118
	db 105
	db 100
	db 101
	db 100
	db 32
	db 116
	db 104
	db 97
	db 116
	db 32
	db 116
	db 104
	db 101
	db 32
	db 102
	db 111
	db 108
	db 108
	db 111
	db 119
	db 105
	db 110
	db 103
	db 32
	db 99
	db 111
	db 110
	db 100
	db 105
	db 116
	db 105
	db 111
	db 110
	db 115
	db 32
	db 97
	db 114
	db 101
	db 32
	db 109
	db 101
	db 116
	db 58
	db 13
	db 10
	db 13
	db 10
	db 49
	db 46
	db 32
	db 82
	db 101
	db 100
	db 105
	db 115
	db 116
	db 114
	db 105
	db 98
	db 117
	db 116
	db 105
	db 111
	db 110
	db 115
	db 32
	db 111
	db 102
	db 32
	db 115
	db 111
	db 117
	db 114
	db 99
	db 101
	db 32
	db 99
	db 111
	db 100
	db 101
	db 32
	db 109
	db 117
	db 115
	db 116
	db 32
	db 114
	db 101
	db 116
	db 97
	db 105
	db 110
	db 32
	db 116
	db 104
	db 101
	db 32
	db 97
	db 98
	db 111
	db 118
	db 101
	db 32
	db 99
	db 111
	db 112
	db 121
	db 114
	db 105
	db 103
	db 104
	db 116
	db 32
	db 110
	db 111
	db 116
	db 105
	db 99
	db 101
	db 44
	db 13
	db 10
	db 116
	db 104
	db 105
	db 115
	db 32
	db 108
	db 105
	db 115
	db 116
	db 32
	db 111
	db 102
	db 32
	db 99
	db 111
	db 110
	db 100
	db 105
	db 116
	db 105
	db 111
	db 110
	db 115
	db 32
	db 97
	db 110
	db 100
	db 32
	db 116
	db 104
	db 101
	db 32
	db 102
	db 111
	db 108
	db 108
	db 111
	db 119
	db 105
	db 110
	db 103
	db 32
	db 100
	db 105
	db 115
	db 99
	db 108
	db 97
	db 105
	db 109
	db 101
	db 114
	db 46
	db 13
	db 10
	db 13
	db 10
	db 50
	db 46
	db 32
	db 82
	db 101
	db 100
	db 105
	db 115
	db 116
	db 114
	db 105
	db 98
	db 117
	db 116
	db 105
	db 111
	db 110
	db 115
	db 32
	db 105
	db 110
	db 32
	db 98
	db 105
	db 110
	db 97
	db 114
	db 121
	db 32
	db 102
	db 111
	db 114
	db 109
	db 32
	db 109
	db 117
	db 115
	db 116
	db 32
	db 114
	db 101
	db 112
	db 114
	db 111
	db 100
	db 117
	db 99
	db 101
	db 32
	db 116
	db 104
	db 101
	db 32
	db 97
	db 98
	db 111
	db 118
	db 101
	db 32
	db 99
	db 111
	db 112
	db 121
	db 114
	db 105
	db 103
	db 104
	db 116
	db 32
	db 110
	db 111
	db 116
	db 105
	db 99
	db 101
	db 44
	db 13
	db 10
	db 116
	db 104
	db 105
	db 115
	db 32
	db 108
	db 105
	db 115
	db 116
	db 32
	db 111
	db 102
	db 32
	db 99
	db 111
	db 110
	db 100
	db 105
	db 116
	db 105
	db 111
	db 110
	db 115
	db 32
	db 97
	db 110
	db 100
	db 32
	db 116
	db 104
	db 101
	db 32
	db 102
	db 111
	db 108
	db 108
	db 111
	db 119
	db 105
	db 110
	db 103
	db 32
	db 100
	db 105
	db 115
	db 99
	db 108
	db 97
	db 105
	db 109
	db 101
	db 114
	db 32
	db 105
	db 110
	db 32
	db 116
	db 104
	db 101
	db 32
	db 100
	db 111
	db 99
	db 117
	db 109
	db 101
	db 110
	db 116
	db 97
	db 116
	db 105
	db 111
	db 110
	db 13
	db 10
	db 97
	db 110
	db 100
	db 47
	db 111
	db 114
	db 32
	db 111
	db 116
	db 104
	db 101
	db 114
	db 32
	db 109
	db 97
	db 116
	db 101
	db 114
	db 105
	db 97
	db 108
	db 115
	db 32
	db 112
	db 114
	db 111
	db 118
	db 105
	db 100
	db 101
	db 100
	db 32
	db 119
	db 105
	db 116
	db 104
	db 32
	db 116
	db 104
	db 101
	db 32
	db 100
	db 105
	db 115
	db 116
	db 114
	db 105
	db 98
	db 117
	db 116
	db 105
	db 111
	db 110
	db 46
	db 13
	db 10
	db 13
	db 10
	db 84
	db 72
	db 73
	db 83
	db 32
	db 83
	db 79
	db 70
	db 84
	db 87
	db 65
	db 82
	db 69
	db 32
	db 73
	db 83
	db 32
	db 80
	db 82
	db 79
	db 86
	db 73
	db 68
	db 69
	db 68
	db 32
	db 66
	db 89
	db 32
	db 84
	db 72
	db 69
	db 32
	db 67
	db 79
	db 80
	db 89
	db 82
	db 73
	db 71
	db 72
	db 84
	db 32
	db 72
	db 79
	db 76
	db 68
	db 69
	db 82
	db 83
	db 32
	db 65
	db 78
	db 68
	db 32
	db 67
	db 79
	db 78
	db 84
	db 82
	db 73
	db 66
	db 85
	db 84
	db 79
	db 82
	db 83
	db 32
	db 34
	db 65
	db 83
	db 32
	db 73
	db 83
	db 34
	db 13
	db 10
	db 65
	db 78
	db 68
	db 32
	db 65
	db 78
	db 89
	db 32
	db 69
	db 88
	db 80
	db 82
	db 69
	db 83
	db 83
	db 32
	db 79
	db 82
	db 32
	db 73
	db 77
	db 80
	db 76
	db 73
	db 69
	db 68
	db 32
	db 87
	db 65
	db 82
	db 82
	db 65
	db 78
	db 84
	db 73
	db 69
	db 83
	db 44
	db 32
	db 73
	db 78
	db 67
	db 76
	db 85
	db 68
	db 73
	db 78
	db 71
	db 44
	db 32
	db 66
	db 85
	db 84
	db 32
	db 78
	db 79
	db 84
	db 32
	db 76
	db 73
	db 77
	db 73
	db 84
	db 69
	db 68
	db 32
	db 84
	db 79
	db 44
	db 32
	db 84
	db 72
	db 69
	db 13
	db 10
	db 73
	db 77
	db 80
	db 76
	db 73
	db 69
	db 68
	db 32
	db 87
	db 65
	db 82
	db 82
	db 65
	db 78
	db 84
	db 73
	db 69
	db 83
	db 32
	db 79
	db 70
	db 32
	db 77
	db 69
	db 82
	db 67
	db 72
	db 65
	db 78
	db 84
	db 65
	db 66
	db 73
	db 76
	db 73
	db 84
	db 89
	db 32
	db 65
	db 78
	db 68
	db 32
	db 70
	db 73
	db 84
	db 78
	db 69
	db 83
	db 83
	db 32
	db 70
	db 79
	db 82
	db 32
	db 65
	db 32
	db 80
	db 65
	db 82
	db 84
	db 73
	db 67
	db 85
	db 76
	db 65
	db 82
	db 32
	db 80
	db 85
	db 82
	db 80
	db 79
	db 83
	db 69
	db 13
	db 10
	db 65
	db 82
	db 69
	db 32
	db 68
	db 73
	db 83
	db 67
	db 76
	db 65
	db 73
	db 77
	db 69
	db 68
	db 46
	db 32
	db 73
	db 78
	db 32
	db 78
	db 79
	db 32
	db 69
	db 86
	db 69
	db 78
	db 84
	db 32
	db 83
	db 72
	db 65
	db 76
	db 76
	db 32
	db 84
	db 72
	db 69
	db 32
	db 67
	db 79
	db 80
	db 89
	db 82
	db 73
	db 71
	db 72
	db 84
	db 32
	db 72
	db 79
	db 76
	db 68
	db 69
	db 82
	db 32
	db 79
	db 82
	db 32
	db 67
	db 79
	db 78
	db 84
	db 82
	db 73
	db 66
	db 85
	db 84
	db 79
	db 82
	db 83
	db 32
	db 66
	db 69
	db 13
	db 10
	db 76
	db 73
	db 65
	db 66
	db 76
	db 69
	db 32
	db 70
	db 79
	db 82
	db 32
	db 65
	db 78
	db 89
	db 32
	db 68
	db 73
	db 82
	db 69
	db 67
	db 84
	db 44
	db 32
	db 73
	db 78
	db 68
	db 73
	db 82
	db 69
	db 67
	db 84
	db 44
	db 32
	db 73
	db 78
	db 67
	db 73
	db 68
	db 69
	db 78
	db 84
	db 65
	db 76
	db 44
	db 32
	db 83
	db 80
	db 69
	db 67
	db 73
	db 65
	db 76
	db 44
	db 32
	db 69
	db 88
	db 69
	db 77
	db 80
	db 76
	db 65
	db 82
	db 89
	db 44
	db 32
	db 79
	db 82
	db 13
	db 10
	db 67
	db 79
	db 78
	db 83
	db 69
	db 81
	db 85
	db 69
	db 78
	db 84
	db 73
	db 65
	db 76
	db 32
	db 68
	db 65
	db 77
	db 65
	db 71
	db 69
	db 83
	db 32
	db 40
	db 73
	db 78
	db 67
	db 76
	db 85
	db 68
	db 73
	db 78
	db 71
	db 44
	db 32
	db 66
	db 85
	db 84
	db 32
	db 78
	db 79
	db 84
	db 32
	db 76
	db 73
	db 77
	db 73
	db 84
	db 69
	db 68
	db 32
	db 84
	db 79
	db 44
	db 32
	db 80
	db 82
	db 79
	db 67
	db 85
	db 82
	db 69
	db 77
	db 69
	db 78
	db 84
	db 32
	db 79
	db 70
	db 13
	db 10
	db 83
	db 85
	db 66
	db 83
	db 84
	db 73
	db 84
	db 85
	db 84
	db 69
	db 32
	db 71
	db 79
	db 79
	db 68
	db 83
	db 32
	db 79
	db 82
	db 32
	db 83
	db 69
	db 82
	db 86
	db 73
	db 67
	db 69
	db 83
	db 59
	db 32
	db 76
	db 79
	db 83
	db 83
	db 32
	db 79
	db 70
	db 32
	db 85
	db 83
	db 69
	db 44
	db 32
	db 68
	db 65
	db 84
	db 65
	db 44
	db 32
	db 79
	db 82
	db 32
	db 80
	db 82
	db 79
	db 70
	db 73
	db 84
	db 83
	db 59
	db 32
	db 79
	db 82
	db 32
	db 66
	db 85
	db 83
	db 73
	db 78
	db 69
	db 83
	db 83
	db 13
	db 10
	db 73
	db 78
	db 84
	db 69
	db 82
	db 82
	db 85
	db 80
	db 84
	db 73
	db 79
	db 78
	db 41
	db 32
	db 72
	db 79
	db 87
	db 69
	db 86
	db 69
	db 82
	db 32
	db 67
	db 65
	db 85
	db 83
	db 69
	db 68
	db 32
	db 65
	db 78
	db 68
	db 32
	db 79
	db 78
	db 32
	db 65
	db 78
	db 89
	db 32
	db 84
	db 72
	db 69
	db 79
	db 82
	db 89
	db 32
	db 79
	db 70
	db 32
	db 76
	db 73
	db 65
	db 66
	db 73
	db 76
	db 73
	db 84
	db 89
	db 44
	db 32
	db 87
	db 72
	db 69
	db 84
	db 72
	db 69
	db 82
	db 32
	db 73
	db 78
	db 13
	db 10
	db 67
	db 79
	db 78
	db 84
	db 82
	db 65
	db 67
	db 84
	db 44
	db 32
	db 83
	db 84
	db 82
	db 73
	db 67
	db 84
	db 32
	db 76
	db 73
	db 65
	db 66
	db 73
	db 76
	db 73
	db 84
	db 89
	db 44
	db 32
	db 79
	db 82
	db 32
	db 84
	db 79
	db 82
	db 84
	db 32
	db 40
	db 73
	db 78
	db 67
	db 76
	db 85
	db 68
	db 73
	db 78
	db 71
	db 32
	db 78
	db 69
	db 71
	db 76
	db 73
	db 71
	db 69
	db 78
	db 67
	db 69
	db 32
	db 79
	db 82
	db 32
	db 79
	db 84
	db 72
	db 69
	db 82
	db 87
	db 73
	db 83
	db 69
	db 41
	db 13
	db 10
	db 65
	db 82
	db 73
	db 83
	db 73
	db 78
	db 71
	db 32
	db 73
	db 78
	db 32
	db 65
	db 78
	db 89
	db 32
	db 87
	db 65
	db 89
	db 32
	db 79
	db 85
	db 84
	db 32
	db 79
	db 70
	db 32
	db 84
	db 72
	db 69
	db 32
	db 85
	db 83
	db 69
	db 32
	db 79
	db 70
	db 32
	db 84
	db 72
	db 73
	db 83
	db 32
	db 83
	db 79
	db 70
	db 84
	db 87
	db 65
	db 82
	db 69
	db 44
	db 32
	db 69
	db 86
	db 69
	db 78
	db 32
	db 73
	db 70
	db 32
	db 65
	db 68
	db 86
	db 73
	db 83
	db 69
	db 68
	db 32
	db 79
	db 70
	db 32
	db 84
	db 72
	db 69
	db 13
	db 10
	db 80
	db 79
	db 83
	db 83
	db 73
	db 66
	db 73
	db 76
	db 73
	db 84
	db 89
	db 32
	db 79
	db 70
	db 32
	db 83
	db 85
	db 67
	db 72
	db 32
	db 68
	db 65
	db 77
	db 65
	db 71
	db 69
	db 46
	db 36
