/*
 * arm v7 reboot code
 *
 * must fit in 11K to avoid stepping on PTEs; see mem.h.
 * cache parameters are at CACHECONF.
 */
#include "arm.s"

/*
 * All caches but L1 should be off before calling this.
 * Turn off MMU, then copy the new kernel to its correct location
 * in physical memory.  Then jump to the start of the kernel.
 */

/* main(PADDR(entry), PADDR(code), size); */
TEXT	main(SB), 1, $-4
	MOVW	$setR12(SB), R12
	MOVW	R0, p1+0(FP)		/* destination, passed in R0 */
	CPSID				/* splhi */

PUTC('R')
	BL	cachesoff(SB)
	/* now back in 29- or 26-bit addressing, mainly for SB */
	/* double mapping of PHYSDRAM & KZERO now in effect */

PUTC('e')
	/* before turning MMU off, switch to PHYSDRAM-based addresses */
	DMB

	MOVW	$KSEGM, R7		/* clear segment bits */
	MOVW	$PHYSDRAM, R0		/* set dram base bits */
	BIC	R7, R12			/* adjust SB */
	ORR	R0, R12

	BL	_r15warp(SB)
	/* don't care about saving R14; we're not returning */

	/*
	 * now running in PHYSDRAM segment, not KZERO.
	 */

PUTC('b')
	/* invalidate mmu mappings */
	MOVW	$KZERO, R0			/* some valid virtual address */
	MTCP	CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinv
	BARRIERS

PUTC('o')
	/*
	 * turn the MMU off
	 */
	MFCP	CpSC, 0, R0, C(CpCONTROL), C(0)
	BIC	$CpCmmu, R0
	MTCP	CpSC, 0, R0, C(CpCONTROL), C(0)
	BARRIERS

PUTC('o')
	/* copy in arguments from stack frame before moving stack */
	MOVW	p2+4(FP), R4		/* phys source */
	MOVW	n+8(FP), R5		/* byte count */
	MOVW	p1+0(FP), R6		/* phys destination */

	/* set up a new stack for local vars and memmove args */
	MOVW	R6, SP			/* tiny trampoline stack */
	SUB	$(0x20 + 4), SP		/* back up before a.out header */

//	MOVW	R14, -48(SP)		/* store return addr */
	SUB	$48, SP			/* allocate stack frame */

	MOVW	R5, 40(SP)		/* save count */
	MOVW	R6, 44(SP)		/* save dest/entry */

	/* copy the new kernel into place */
	DELAY(printloop2, 2)
PUTC('t')
	MOVW	40(SP), R5		/* restore count */
	MOVW	44(SP), R6		/* restore dest/entry */
	MOVW	R6, 0(SP)		/* normally saved LR goes here */
	MOVW	R6, 4(SP)		/* push dest */
	MOVW	R6, R0
	MOVW	R4, 8(SP)		/* push src */
	MOVW	R5, 12(SP)		/* push size */
	BL	memmove(SB)

PUTC('-')
PUTC('>')
	DELAY(printloopret, 1)
PUTC('\r')
	DELAY(printloopnl, 1)
PUTC('\n')
/*
 * jump to kernel entry point.  Note the true kernel entry point is
 * the virtual address KZERO|R6, but this must wait until
 * the MMU is enabled by the kernel in l.s
 */
	MOVW	44(SP), R6		/* restore R6 (dest/entry) */
	ORR	R6, R6			/* NOP: avoid link bug */
	B	(R6)
PUTC('?')
PUTC('?')
	B	0(PC)

/*
 * turn the caches off, double map PHYSDRAM & KZERO, invalidate TLBs, revert
 * to tiny addresses.  upon return, it will be safe to turn off the mmu.
 */
TEXT cachesoff(SB), 1, $-4
	MOVM.DB.W [R14,R1-R10], (R13)		/* save regs on stack */
	CPSID
	BARRIERS

	SUB	$12, SP				/* paranoia */
	BL	cacheuwbinv(SB)
	ADD	$12, SP				/* paranoia */

	MFCP	CpSC, 0, R0, C(CpCONTROL), C(0)
	BIC	$(CpCicache|CpCdcache), R0
	MTCP	CpSC, 0, R0, C(CpCONTROL), C(0)	/* caches off */
	BARRIERS

	/*
	 * caches are off
	 */

	/* invalidate stale TLBs before changing them */
	MOVW	$KZERO, R0			/* some valid virtual address */
	MTCP	CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinv
	BARRIERS

	/* redo double map of PHYSDRAM, KZERO */
	MOVW	$PHYSDRAM, R3
	CMP	$KZERO, R3
	BEQ	noun2map
	MOVW	$(L1+L1X(PHYSDRAM)), R4		/* address of PHYSDRAM's PTE */
	MOVW	$PTEDRAM, R2			/* PTE bits */
	MOVW	$DOUBLEMAPMBS, R5
_ptrdbl:
	ORR	R3, R2, R1		/* first identity-map 0 to 0, etc. */
	MOVW	R1, (R4)
	ADD	$4, R4				/* bump PTE address */
	ADD	$MiB, R3			/* bump pa */
	SUB.S	$1, R5
	BNE	_ptrdbl
noun2map:

	/*
	 * flush stale TLB entries
	 */

	BARRIERS
	MOVW	$KZERO, R0			/* some valid virtual address */
	MTCP	CpSC, 0, R0, C(CpTLB), C(CpTLBinvu), CpTLBinv
	BARRIERS

	/* switch back to PHYSDRAM addressing, mainly for SB */
	MOVW	$KSEGM, R7		/* clear segment bits */
	MOVW	$PHYSDRAM, R0		/* set dram base bits */
	BIC	R7, R12			/* adjust SB */
	ORR	R0, R12
	BIC	R7, SP
	ORR	R0, SP

	MOVM.IA.W (R13), [R14,R1-R10]		/* restore regs from stack */

	MOVW	$KSEGM, R0		/* clear segment bits */
	BIC	R0, R14			/* adjust link */
	MOVW	$PHYSDRAM, R0		/* set dram base bits */
	ORR	R0, R14

	RET

TEXT _r15warp(SB), 1, $-4
	BIC	R7, R14			/* link */
	ORR	R0, R14

	BIC	R7, R13			/* SP */
	ORR	R0, R13
	RET

TEXT panic(SB), 1, $-4		/* stub */
PUTC('?')
PUTC('!')
	RET
TEXT pczeroseg(SB), 1, $-4	/* stub */
	RET

#include "cache.v7.s"

/* modifies R0, R3???R6 */
TEXT printhex(SB), 1, $-4
	MOVW	R0, R3
	MOVW	$(32-4), R5	/* bits to shift right */
nextdig:
	SRA	R5, R3, R4
	AND	$0xf, R4
	ADD	$'0', R4
	CMP.S	$'9', R4
	BLE	nothex		/* if R4 <= 9, jump */
	ADD	$('a'-('9'+1)), R4
nothex:
	PUTC(R4)
	SUB.S	$4, R5
	BGE	nextdig

	PUTC('\r')
	PUTC('\n')
	DELAY(proct, 50)
	RET
