
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbrs EDX
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret
/* void mp1_rtc_tasklet (unsigned long)
 * 
 * info: the tasklet updates the stae of the game - it is called when an RTC interrupt is generated. It traverses the list that mp1_list_head points to,
 * decrementing the countdown field of the structure. If the countdown decrements to 0, then the tasklet looks at the status and sets 
 * it to the opposite setting (1 to 0 and 0 to 1 where 0 is off_char and 1 is on_char).
 * It then copies the value of the opposite field length (1 to off_length and 0 to on_length). 
 *      Interface: 
 *      input: 
 *      output: none because it's void
 * registers: 
 *      esi = current node being traversed
 *      ecx = countdown field of structure currently pointed to
 *      eax, edx = temp
 */
mp1_rtc_tasklet:
        /* set stack */
        pushl %ebp
        movl %esp, %ebp
        pushl %esi                      
        movl mp1_list_head, %esi        /* esi = head */

tasklet_loop:

        /*check that head is not NULL */
        cmpl $0, %esi
        je finished_tasklet

        xorl %ecx, %ecx
        movw COUNTDOWN(%esi), %cx       /* ecx = countdown */
        addl $-1, %ecx                  /* decrement countdown */
        movw %cx, COUNTDOWN(%esi)       /* update countdown */
        cmpl $0, %ecx                   /* if countdown reaches 0, switch the light to its opposite, else go to the next node */
        jne next_node

        /*check if status field = 1, if so the node is currently on, else the node is currently off*/
        xorl %edx, %edx
        movw STATUS(%esi), %dx
        cmpl $1, %edx
        je tasklet_on_char
tasklet_off_char:
        addl $1, %edx                   /* change status to 1 */
        movw %dx, STATUS(%esi);
        pushl %ecx                      
        pushl %esi                      
        /* set appropriate registers - eax, cl */
        xorl %eax, %eax
        movb ON_CHAR(%esi), %cl 
        movw LOCATION(%esi), %ax
        salw $1, %ax                    /* multiply location by 2 */
        call mp1_poke
        popl %esi
        popl %ecx

        /* the tasklet updates the countdown field by copying the value from the opposite length field to countdown. */
        movw ON_LENGTH(%esi), %dx
        movw %dx, COUNTDOWN(%esi)

        /*go to next node */
        jmp next_node
tasklet_on_char:
        addl $-1, %edx                  /* change status to 0 */
        movw %dx, STATUS(%esi);
        pushl %ecx
        pushl %esi
        /* set appropriate register - eax, cl */
        xorl %eax, %eax
        movb OFF_CHAR(%esi), %cl
        movw LOCATION(%esi), %ax
        salw $1, %ax                    /* multiply location by 2 */
        call mp1_poke
        popl %esi
        popl %ecx

        /* the tasklet updates the countdown field by copying the value from the opposite length field to countdown. */
        movw OFF_LENGTH(%esi), %dx
        movw %dx, COUNTDOWN(%esi)
next_node:
        movl NEXT(%esi), %esi     /* esi = next */

        jmp tasklet_loop

finished_tasklet:
        leave
	ret
/* int mp1_ioctl (unsigned long arg, unsigned long cmd);
 * 
 * info: a "dispatcher" function that calles the different core functions : mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find and mp1_ioctl_sync depending on the acm argument.
 *      Interface: stack-based arguments
 *      input: 
 *               arg - the argument to be passed on into the Core function
 *               cmd - determines which core function to call
 *      output: 
 *               -1 if invalid
 *               whatever the core function calls
 * registers: 
 *      ebx = cmd
 *      ecx = arg
 */
mp1_ioctl:
        movl 8(%esp), %ebx             /* ebx = cmd */
        movl 4(%esp), %ecx              /* ecx = arg */

        /* check what cmd is */
        cmpl $3, %ebx 
        ja mp1_ioctl_invalid           /* if cmd is above 3, return -1 */
        jmp *jump_table(, %ebx, 4)
	ret 
/* int mp1 ioctl add(unsigned long arg)
 * 
 * info: add a node to the linked list. Allocates memory using mp1_malloc. 
 *      Interface: register-based arguments
 *      input: 
 *               arg - a user-level pointer to a mp1_blink_struct structure that has to be added to the linked list - adds to the beginning of the list
 *      output: 
 *               -1 if invalid
 *              0 if successful
 * registers: 
 *      ecx = arg 
 *      ebx = the pointer that malloc returns - which is what's going to be added to the linked list
 */   
mp1_ioctl_add:
        /* create stack */
        pushl %ebp
        movl %esp, %ebp

        /* check that argument is not 0 */
        cmpl $0, %ecx
        je mp1_ioctl_invalid

        /* call malloc */
        pushl %ecx
        pushl $STRUCT_SIZE                      /* push size */
        call mp1_malloc
        addl $4, %esp                          /* pop */
        popl %ecx

        movl %eax, %ebx                       /*ebx = malloc's return */

        /* check that mp1_malloc didn't return 0 */
        cmpl $0, %ebx
        je mp1_ioctl_invalid

        /* call mp1_copy_from_user - to = arg, from = malloc */
        pushl $STRUCT_SIZE              /* push */
        pushl %ecx
        pushl %ebx
        call mp1_copy_from_user
        popl %ebx                       /* pop */
        popl %ecx
        addl $4, %esp

        /* cehck that the return value is 0 */
        cmpl $0, %eax
        jne copy_error

        /*  Check if the location is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, LOCATION(%ebx)                      
        ja location_error

        /* COUNTDOWN = ON_LENGTH */
        movw ON_LENGTH(%ebx), %ax
        movw %ax, COUNTDOWN(%ebx)

        /*set STATUS to 1 */
        movw $1, STATUS(%ebx)
        
        /* next = head */
        movl mp1_list_head, %eax
        movl %eax, NEXT(%ebx)

        /* store address of structure to mp1_list_head */
        movl %ebx, mp1_list_head

        /* put in correct parameters into correct registers */
        xorl %eax, %eax
        movb ON_CHAR(%ebx), %cl
        movw LOCATION(%ebx), %ax
        salw $1, %ax

        /* save edx and call poke */
        pushl %edx
        call mp1_poke
        popl %edx

        leave
	ret
 /* int mp1 ioctl remove(unsigned long arg)
 * 
 * info: looks in the linked list for the struct with the same location as the argument, then removes that node and frees
 *      Interface: register-based arguments
 *      input: 
 *               arg - the location of the node that needs to be found (ecx)
 *      output: 
 *               -1 if invalid
 *               0 if successful
 * registers: 
 *      ecx = arg
 *      edx = LOCATION used to search in the linked list
 *      esi = points to the current node while being traversed
 */        
mp1_ioctl_remove:
        /* ecx = argument */

        /* set stack */
        pushl %ebp
        movl %esp, %ebp
        pushl %edx
        pushl %esi

        /* check that argument is not 0 */
        cmpl $0, %ecx
        je find_invalid

        /*  Check if the location is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, %cx                      
        ja remove_error

        /*put LOCATION  to be found in edx */
        xorl %edx, %edx
        movw %cx, %dx

        /* check if the node looking for is head */
        xorl %eax, %eax
        movl mp1_list_head, %esi                /* esi = head */

        cmpl $0, %esi
        je remove_error

        movw LOCATION(%esi), %ax
        cmpw %dx, %ax
        jne call_search_helper

        /*remove from list by moving head */
        movl NEXT(%esi), %eax
        movl %eax, mp1_list_head
        jmp remove_free

call_search_helper:
        /*get the node before the node to be found using search_helper */
        call search_helper

        /* check that it was found */
        cmpl $-1, %eax
        je remove_error

        /* put returned address into register %ecx and the node to remove into %esi*/
        movl %eax, %ecx
        movl NEXT(%ecx), %esi

        /*remove from the list */
        movl NEXT(%esi), %eax
        movl %eax, NEXT(%ecx)

remove_free:
        /* free malloced(?) memory */
        pushl %esi
        call mp1_free
        popl %esi

        /* return 0 for success */
        xorl %eax, %eax
        popl %esi
        popl %edx
	leave
        ret

/* int mp1 ioctl find(unsigned long arg)
 * 
 * info: looks in the linked list for the element that matches the location and copies the element to the user-level structure
 *      Interface: register-based arguments
 *      input: 
 *               arg - a pointer to a mp1_blinlk_struct
 *      output: 
 *               -1 if invalid
 *               0 if successful
 * registers: 
 *      ecx = arg
 *      edi = current node when traversing the list
 *      eax = temp and output
 */     
mp1_ioctl_find:
        /* set stack */
        pushl %ebp
        movl %esp, %ebp
        pushl %edi

        /* check that argument is not 0 */
        cmpl $0, %ecx
        je find_invalid

        movl mp1_list_head, %edi        /* set edi to head */

        /*  Check if the location of edi is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, LOCATION(%edi)                      
        ja find_invalid

        /*  Check if the location of ecx is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, LOCATION(%ecx)                      
        ja find_invalid

        /* traverse the list until arg's location is found */
find_loop:
        /* check that ebx is not pointing to NULL */
        cmpl $0, %edi
        je find_invalid
        /*check if current node's location is same as arg's location. */
        xorl %eax, %eax
        xorl %edx, %edx
        movw LOCATION(%edi), %ax
        movw LOCATION(%ecx), %dx
        cmpw %ax, %dx
        je find_found
        /** go to next node */
        movl NEXT(%edi), %edi     /* ebx = next */
        jmp find_loop

find_found:

        /* call mp1_copy_to_user with appropriate registers */
        /* to = ecx, from = ebx, n = STRUCT_SIZE*/
        pushl $STRUCT_SIZE
        pushl %edi
        pushl %ecx
        call mp1_copy_to_user
        popl %ecx
        popl %edi
        addl $4, %esp

        /* check that return value is 0 */
        cmpl $0, %eax
        je find_invalid

        xorl %eax, %eax
        popl %edi
	leave
        ret
/* int mp1 ioctl sync(unsigned long arg)
 * 
 * info: the arg contains two locations (one in the upper half and one in the lower half) and syncs the two's timing information (from the first element to the second element)
 *      Interface: register-based arguments
 *      input: 
 *               arg - two two-byte unsigned short integers passed in as one four-byte argument. The upper 16 bits has the first integer and the lower 16 bits has the second integer
 *      output: 
 *               -1 if invalid
 *               0 if successful
 * registers: 
 *      ecx = arg
 *      edx = first integer (upper 16 bits)
 *      ebx = second integer (lower 16 bits)
 *      esi = points to the node being traversed
 */   
mp1_ioctl_sync:
        /* create stack */
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx

        /* ecx = arg */
        /* check that argument is not 0 */
        cmpl $0, %ecx
        je find_invalid

        /* extract two integers from the argument */
        /* first = upper 16 bits - dx, second = lower 16 bits - bx */
        xorl %ebx, %ebx
        movw %cx, %bx                           /* bx = lower half */
        xorl %edx, %edx
        movl %ecx, %edx
        sarl $16, %edx                          /* dx = upper half */

        /* search for location of upper half */
search_sync_upper:

        /* check if it's at head */
        movl mp1_list_head, %eax
        movw LOCATION(%eax), %cx
        cmpw %cx, %dx
        jne call_search_upper

        movl mp1_list_head, %edx

        jmp search_sync_lower
        /* call search_helper for the first integer which should return the node before it */
call_search_upper:
        pushl %edx
        call search_helper
        popl %edx

        /* check that it didn't return -1 */
        cmpl $-1, %eax
        je sync_invalid

        /* check that it didn't return -1 */
        cmpl $0, %eax
        je sync_invalid

        /* go to the actual node found */
        movl NEXT(%eax), %edx
        
        /* call search_helper for the second integer which should return the node before it */
search_sync_lower:

        /* check if it's at head */
        movl mp1_list_head, %eax
        movw LOCATION(%eax), %cx
        cmpw %cx, %bx
        jne call_search_lower

        movl mp1_list_head, %ebx

        jmp sync_integers_found
call_search_lower:
        pushl %edx
        xorl %edx, %edx
        movw %bx, %dx
        call search_helper
        popl %edx

        cmpl $-1, %eax
        je sync_invalid

        cmpl $0, %eax
        je sync_invalid

        movl NEXT(%eax), %ebx


sync_integers_found:

        /* copy timing info from first element (edx) to second element (ebx) - on_length, off_length, countdown and status */

        movw ON_LENGTH(%edx), %ax
        movw %ax, ON_LENGTH(%ebx)

        movw OFF_LENGTH(%edx), %ax
        movw %ax, OFF_LENGTH(%ebx)

        movw COUNTDOWN(%edx), %ax
        movw %ax, COUNTDOWN(%ebx)

        movw STATUS(%edx), %ax
        movw %ax, STATUS(%ebx)

        /* check status and go to on or off */
        movw STATUS(%ebx), %ax
        cmpw $0, %ax
        je sync_off_char

        /* set appropriate parameters depending on if it's on or off*/
        /* Inputs:      %cl  - The byte you wish to write
                        %eax - Offset from the start of video memory that you wish
                        to write to 
        */
sync_on_char:
        xorl %eax, %eax
        movw LOCATION(%ebx), %ax 
        movb ON_CHAR(%ebx), %cl
        salw $1, %ax

        jmp sync_call_poke

sync_off_char:
        xorl %eax, %eax
        movw LOCATION(%ebx), %ax 
        movb OFF_CHAR(%ebx), %cl
        salw $1, %ax

sync_call_poke:
        pushl %edx
        call mp1_poke
        popl %edx
/* return 0 for success */
        xorl %eax, %eax
        popl %ebx
	leave
        ret
/* Used to call the different core functions depending on the cmd value
 *      jump_table[0] = mp1_ioctl_add
 *      jump_table[1] = mp1_ioctl_remove 
 *      jump_table[2] = mp1_ioctl_find
 *      jump_table[3] = mp1_ioctl_sync 
 */
jump_table:
        .long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync


/* The functions below has the caller function return -1 because something was invalid */
mp1_ioctl_invalid:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax
        leave
        ret
find_invalid:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax
        popl %edi
        leave
        ret
sync_invalid:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax
        popl %ebx
        leave
        ret

search_invalid:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax
        popl %esi
        leave
        ret
copy_error:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax

        /* free malloced(?) memory */
        pushl %ebx
        call mp1_free
        popl %ebx

        leave
        ret 
location_error:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax

        /* free malloced(?) memory */
        pushl %ebx
        call mp1_free
        popl %ebx
        leave
        ret
remove_error:
        /* return -1*/
        xorl %eax, %eax
        addl $-1, %eax
        leave
        ret


/* 
 * info: a helper function used to find the structure in the linked list that has the matching location - used for sync and remove.
 *      THE CALLER SHOULD CHECK THAT THE STRUCTURE THAT IT'S LOOKING FOR IS NOT THE HEAD BEFORE CALLING THIS FUNCTION.
 *      Interface: register-based arguments
 *      input: 
 *               edx - location of the struct you want to find
 *      output: 
 *               the previous node of the one to be found
 * registers: 
 *      edx = has the location of node you want to find
 *      esi = points to the node being traversed
 *      eax = temp
 *      ebx = previos node
 */  

        /** edx has the location of node you want to find */
search_helper:
        /* set stack */
        pushl %ebp
        movl %esp, %ebp
        pushl %esi
        pushl %ebx

        movl mp1_list_head, %esi        /* set esi to head */

        /*  Check if the location of esi is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, LOCATION(%esi)                      
        ja search_invalid

        /*  Check if the location of ecx is outside the valid range of 0 to 80*25-1 (= 1999) */ 
        cmpw $1999, %dx                      
        ja search_invalid

        /* traverse the list until arg's location is found */
search_loop:
        /* check that esi is not pointing to NULL */
        cmpl $0, %esi
        je search_invalid
        /*check if current node's location is same as arg's location. */
        xorl %eax, %eax
        movw LOCATION(%esi), %ax
        cmpw %ax, %dx
        je search_found
        /** go to next node */
        movl %esi, %ebx
        movl NEXT(%esi), %esi     /* esi = next */
        jmp search_loop

search_found:
        /* put ebx into eax so it returns the previous node */
        movl %ebx, %eax
        popl %ebx
        popl %esi
        leave
        ret

.end
