.section .vectors, "ax"
	B _start 		// reset vector
	B SERVICE_UND 		// undefined instruction vector
	B SERVICE_SVC 		// software interrrupt vector
	B SERVICE_ABT_INST 	// aborted prefetch vector
	B SERVICE_ABT_DATA 	// aborted data vector
	.word 0 		// unused vector
	B SERVICE_IRQ 		// IRQ interrupt vector
	B SERVICE_FIQ 		// FIQ interrupt vector
.text
.global _start
_start:

//Set up stack pointers for IRQ and SVC processor modes
MOV R1, #0b11010010 		//interrupts masked, MODE = IRQ
MSR CPSR_c, R1 			//change to IRQ mode
LDR SP, =0xFFFFFFFF - 3 	//set IRQ stack to A9 onchip memory

//Change to SVC (supervisor) mode with interrupts disabled
MOV R1, #0b11010011 		//interrupts masked, MODE = SVC
MSR CPSR, R1 			//change to supervisor mode
LDR SP, =0x3FFFFFFF - 3 	//set SVC stack to top of DDR3 memory
BL CONFIG_GIC 			//configure the ARM GIC

/*
//write to the pushbutton KEY interrupt mask register
LDR R0, =0xFF200050 		//pushbutton KEY base address
MOV R1, #0x8 			//set interrupt mask bits
STR R1, [R0, #0x8] 		//interrupt mask register (base + 8)*/

LDR R0, =0xFFFEC60C 		//Cortex-A9 Private Timer Interrupt status base address
MOV R1, #0x1 			//set interrupt mask bit
STR R1, [R0]			//interrupt mask register

//enable IRQ interrupts in the processor
MOV R0, #0b01010011 // IRQ unmasked, MODE = SVC
MSR CPSR_c, R0

/**
R0		index
R11		message
*/
LDR R11, =WELCOME		//Welcome message
MOV R0, #0			//index
MOV R1, #39			//iteration exit condition
LDR R5, =0xFFFEC600 		//timer address

//Configure timer
LDR r6, =0x5F5E100		//100million
STR r6, [r5] 			//Timer load value

//Load timer controls
MOV R6, #7 			//binary 011 to start counting
STR R6, [R5, #8] 		//+8 -> control adress

WelcomeLoop:
	//Tımer control
	Control:
		LDR R10, =TIMER
		LDR R9, [R10]
		CMP R9, #0x0
		BEQ Control
	
	//Set TIMER 0 again
	MOV R9, #0
	STR R9, [R10]
	BL Display
	ADD R0, R0, #1		//i = i + 1
	
	//check whether loop is finished
	CMP R0, R1
	BEQ end
	
	// TODO TIMER INTERRUPT
	/*DODELAY:	
		LDR R2, =400000		// delay counter
		SUBLOOP:
			SUBS R2, R2, #1
			BNE SUBLOOP*/
	B WelcomeLoop

/**	
Display Subroutine
Displays 8 character into seven segment display
	
INPUT 1		R0	=> index
INPUT 2		R11 => Message 
*/
Display:
	//TODO PUSH
	PUSH {R0,R6-R10,LR}
	LDR R6, =0xFF200020		//Display address
	MOV R7, #0			//initially zero, for loading Welcome characters
	MOV R8, #0			//SUM 4 digits for displaying
	MOV R9, #24			//offset for byte addressable
	MOV R10, #0			//iterator

	Loop:
		ADD R10, R10, #1		//i = i + 1
		//Read character
		LDRB R7, [R11, R0] 		//get first one in the WELCOME
		ADD R8, R8, R7, LSL R9 		//byte addressable offset
		ADD R0, R0, #1			//index = index + 1

		//check whether loop is finished
		CMP R10, #8			//We have 8 display in SSD
		BEQ Finished

		//check for first 4 digit
		SUBS R9, R9, #8			//substract 8 for byte addressable
		BLT Update			//If 4 digit is read
		B Loop
	Update:
		MOV R9, #24			//offset reset	
		STR R8, [R6, #16]		//display first 4 digit
		MOV R8, #0			//reset SUM 4 hex digit
		B Loop
	Finished:
		STR R8, [R6]			//display first 4 digit
		POP {R0, R6-R10,PC}

/* Define the exception service routines */
/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
	B SERVICE_UND
/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
	B SERVICE_SVC
/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
	B SERVICE_ABT_DATA
/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
	B SERVICE_ABT_INST

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
	PUSH {R0-R7, LR}
	/* Read the ICCIAR from the CPU Interface */
	LDR R4, =0xFFFEC100
	LDR R5, [R4, #0x0C] 	//read from ICCIAR
FPGA_IRQ1_HANDLER:
	CMP R5, #29
	UNEXPECTED:
		BNE UNEXPECTED 	//if not recognized, stop here
	TimerInterrupt:
		BL TIMER_ISR
EXIT_IRQ:
	/* Write to the End of Interrupt Register (ICCEOIR) */
	STR R5, [R4, #0x10] 	//write to ICCEOIR
	POP {R0-R7, LR}
	SUBS PC, LR, #4
/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:
	B SERVICE_FIQ

/* ^^^^ END of Define the exception service routines ^^^^ */

/* Configure the Generic Interrupt Controller (GIC)*/
CONFIG_GIC:
	PUSH {LR}
/* CONFIG_INTERRUPT (int_ID (R0), CPU_target (R1)); */
	MOV R0, #29
	MOV R1, #1
	BL CONFIG_INTERRUPT
	
	/* configure the GIC CPU Interface */
	LDR R0, =0xFFFEC100 		// base address of CPU Interface
	
	/* Set Interrupt Priority Mask Register (ICCPMR) */
	LDR R1, =0xFFFF 		// enable interrupts of all priorities levels
	STR R1, [R0, #0x04]
	
	/* Set the enable bit in the CPU Interface Control Register (ICCICR).
	* This allows interrupts to be forwarded to the CPU(s) */
	MOV R1, #1
	STR R1, [R0]
	
	/* Set the enable bit in the Distributor Control Register (ICDDCR).
	* This enables forwarding of interrupts to the CPU Interface(s) */
	LDR R0, =0xFFFED000
	STR R1, [R0]
	POP {PC}

/*
* Configure registers in the GIC for an individual Interrupt ID
* We configure only the Interrupt Set Enable Registers (ICDISERn) and
* Interrupt Processor Target Registers (ICDIPTRn). The default (reset)
* values are used for other registers in the GIC
* Arguments: R0 = Interrupt ID, N
* R1 = CPU target
*/
CONFIG_INTERRUPT:
	PUSH {R4-R5, LR}
/* Configure Interrupt Set-Enable Registers (ICDISERn).
* reg_offset = (integer_div(N / 32) * 4
* value = 1 << (N mod 32) */
	LSR R4, R0, #3 		// calculate reg_offset
	BIC R4, R4, #3 		// R4 = reg_offset
	LDR R2, =0xFFFED100
	ADD R4, R2, R4 		// R4 = address of ICDISER
	AND R2, R0, #0x1F 	// N mod 32
	MOV R5, #1 		// enable
	LSL R2, R5, R2 		// R2 = value
	
/* Using the register address in R4 and the value in R2 set the
* correct bit in the GIC register */
	LDR R3, [R4] 		// read current register value
	ORR R3, R3, R2 		// set the enable bit
	STR R3, [R4] 		// store the new register value
	
/* Configure Interrupt Processor Targets Register (ICDIPTRn)
* reg_offset = integer_div(N / 4) * 4
* index = N mod 4 */
	BIC R4, R0, #3 		// R4 = reg_offset
	LDR R2, =0xFFFED800
	ADD R4, R2, R4 		// R4 = word address of ICDIPTR
	AND R2, R0, #0x3 		// N mod 4
	ADD R4, R2, R4 		// R4 = byte address in ICDIPTR
	
/* Using register address in R4 and the value in R2 write to
* (only) the appropriate byte */
	STRB R1, [R4]
	POP {R4-R5, PC}

/*************************************************************************
* TIMER - Interrupt Service Routine
**************************************************************************/
.equ TIMER_BASE, 0xFFFEC600
TIMER_ISR:
	END_ISR:
		//Toggle TIMER
		LDR R0, =TIMER
		LDR R1, [R0]
		EOR R1, R1, #1
		STR R1, [R0]
		
		//Interrupt Acknowledge
		LDR R0, =TIMER_BASE
		LDR R2, [R0, #12] 	//timer interrupt at 0x0FFFEC600 + 3 bytes
		STR R2, [R0, #12] 	//reset interrupt
		BX LR

end: B end
//WELCOME: HELLO THIS IS ROCK PAPER SCISSORS GAME
WELCOME: .byte 0x76, 0x79, 0x38, 0x38, 0x5C, 0x00, 0x78, 0x76, 0x30, 0x6D,0x00, 0x30, 0x6D,0x00, 0x50, 0x5C, 0x39, 0x75, 0x00, 0x73, 0x77 ,0x73, 0x79, 0x50,0x00, 0x6D, 0x39, 0x30, 0x6D, 0x6D, 0x5C,  0x50, 0x6D,0x00, 0x3D, 0x77, 0x55, 0x79, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,0x00,0x00 
TIMER: .word 0x0 	//initially true
.end