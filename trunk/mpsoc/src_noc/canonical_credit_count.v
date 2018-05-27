`timescale      1ns/1ps

/**********************************************************************
**	File: canonical_credit_counter.v
**    
**	Copyright (C) 2014-2017  Alireza Monemi
**    
**	This file is part of ProNoC 
**
**	ProNoC ( stands for Prototype Network-on-chip)  is free software: 
**	you can redistribute it and/or modify it under the terms of the GNU
**	Lesser General Public License as published by the Free Software Foundation,
**	either version 2 of the License, or (at your option) any later version.
**
** 	ProNoC is distributed in the hope that it will be useful, but WITHOUT
** 	ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
** 	or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General
** 	Public License for more details.
**
** 	You should have received a copy of the GNU Lesser General Public
** 	License along with ProNoC. If not, see <http:**www.gnu.org/licenses/>.
**
**
**	Description: 
**	credit counter for baseline router
*************************************/




module canonical_credit_counter #(

    parameter V = 4, // vc_num_per_port
    parameter P    = 5, // router port num
    parameter B = 4, // buffer space :flit per VC 
    parameter VC_REALLOCATION_TYPE    =    "NONATOMIC",// "ATOMIC" , "NONATOMIC"
    parameter ROUTE_TYPE            =   "ADAPTIVE",// "DETERMINISTIC", "FULL_ADAPTIVE", "PAR_ADAPTIVE"
    parameter CONGESTION_INDEX=2,
    parameter [V-1  :   0] ESCAP_VC_MASK = 4'b0001,  // mask scape vc, valid only for full adaptive
    parameter DEBUG_EN =   1,
    parameter AVC_ATOMIC_EN=0,
    parameter CONGw   =   2 //congestion width per port 
    
)(
    non_ss_ovc_allocated_all,
    flit_is_tail_all,
    assigned_ovc_num_all,
    spec_ovc_num_all,
    dest_port_all,
    nonspec_granted_dest_port_all,
    spec_granted_dest_port_all,
    credit_in_all,
    nonspec_first_arbiter_granted_ivc_all,
    spec_first_arbiter_granted_ivc_all,
    ivc_num_getting_sw_grant,
    ovc_avalable_all,
    assigned_ovc_not_full_all,
    congestion_in_all,
    port_pre_sel,
    ssa_ovc_released_all,
    ssa_ovc_allocated_all, 
    ssa_decreased_credit_in_ss_ovc_all,
    reset,clk
);

 
    function integer log2;
      input integer number; begin   
         log2=(number <=1) ? 1: 0;    
         while(2**log2<number) begin    
            log2=log2+1;    
         end 	   
      end   
    endfunction // log2 
    
    localparam  PV        =    V        *    P,
                VV      =   V       *   V,
                PVV    =    PV        *  V,    
                P_1    =    P-1    ,
                VP_1    =    V        *     P_1,                
                PP_1    =    P_1    *    P,
                PVP_1    =    PV        *    P_1,
                Bw        =    log2(B),
                B_1    =    B-1;        

    localparam  [Bw-1    :    0] Bint    =    B_1[Bw-1    :    0];
    localparam  NORTH  =       3'd2,  
                SOUTH  =       3'd4; 
    localparam  [V-1     :   0] ADAPTIVE_VC_MASK = ~ ESCAP_VC_MASK;  
    localparam  CONG_ALw=   CONGw* P;   //  congestion width per router;

    integer k;                
    input    [PV-1        :    0]    non_ss_ovc_allocated_all;
    input    [PV-1        :    0]    flit_is_tail_all;
    input    [PVV-1        :    0]    assigned_ovc_num_all;
    input    [PVV-1        :    0]    spec_ovc_num_all;
    input    [PVP_1-1    :    0]    dest_port_all;
    input    [PP_1-1        :    0]    nonspec_granted_dest_port_all;
    input    [PP_1-1        :    0]    spec_granted_dest_port_all;
    input    [PV-1        :    0]  credit_in_all;
    input    [PV-1        :    0]    nonspec_first_arbiter_granted_ivc_all;
    input    [PV-1        :    0]    spec_first_arbiter_granted_ivc_all;
    input    [PV-1        :    0]    ivc_num_getting_sw_grant;
    output  [PV-1        :    0]    ovc_avalable_all;
    output  [PV-1        :    0]    assigned_ovc_not_full_all;
    output  [P_1-1      :   0]  port_pre_sel;
    input   [CONG_ALw-1 :   0]  congestion_in_all;

    input                        reset,clk;
//ssa
    input  [PV-1       :    0] ssa_ovc_released_all; 
    input  [PV-1       :    0] ssa_ovc_allocated_all; 
    input  [PV-1       :    0] ssa_decreased_credit_in_ss_ovc_all;
    
    
    
    reg    [PV-1       :    0]    ovc_status;
    reg    [Bw-1       :    0]    credit_counter      [PV-1    :    0];
    reg    [Bw-1       :    0]    credit_counter_next [PV-1    :    0];
    reg    [PV-1       :    0]    full_all,nearly_full_all,full_all_next,nearly_full_all_next;
    
    wire   [PV-1       :    0]    assigned_ovc_is_full_all;
    wire   [VP_1-1     :    0]    credit_decreased        [P-1        :    0];
    wire   [P_1-1      :    0]    credit_decreased_gen    [PV-1        :    0];
    wire   [PV-1       :    0]    non_ss_credit_decreased_all;
    wire   [PV-1       :    0]    credit_increased_all;
    wire   [VP_1-1     :    0]    ovc_released            [P-1        :    0];
    wire   [P_1-1      :    0]    ovc_released_gen        [PV-1        :    0];
    wire   [PV-1       :    0]    non_ss_ovc_released_all;
    wire   [VP_1-1     :    0]    credit_in_perport        [P-1        :    0];
    wire   [VP_1-1     :    0]    full_perport              [P-1        :    0];
    wire   [VP_1-1     :    0]    nearly_full_perport    [P-1        :    0];
    
    
    //ssa
    
    wire [PV-1  :   0] credit_decreased_all;
    wire [PV-1  :   0] ovc_released_all;
    wire [PV-1  :   0] ovc_allocated_all;
    
    assign credit_decreased_all = non_ss_credit_decreased_all | ssa_decreased_credit_in_ss_ovc_all;
    assign ovc_released_all = non_ss_ovc_released_all | ssa_ovc_released_all;
    assign ovc_allocated_all = non_ss_ovc_allocated_all | ssa_ovc_allocated_all;  
    
    
    generate
        /* verilator lint_off WIDTH */
        if(VC_REALLOCATION_TYPE=="ATOMIC") begin :atomic
        /* verilator lint_on WIDTH */
            reg    [PV-1        :    0]    empty_all,empty_all_next;
            
            always @(posedge clk or posedge reset) begin
                for(k=0;    k<PV; k=k+1'b1) begin 
                    if(reset) begin 
                        empty_all[k]    <=    1'b0;
                    end else begin 
                        empty_all[k]    <= empty_all_next[k];
                    end
                end//for
            end//always
    
    
            always @(*) begin
                for(k=0;    k<PV; k=k+1'b1) begin 
                    empty_all_next[k]            =     (credit_counter_next[k]         == Bint);
                end // for    
            end//always
        
            // in atomic architecture an OVC is available if its not allocated and its empty
            assign ovc_avalable_all                 = ~ovc_status & empty_all;
            
        end else begin :nonatomic //NONATOMIC
            /* verilator lint_off WIDTH */
            if(ROUTE_TYPE  == "FULL_ADAPTIVE") begin :full_adpt
            /* verilator lint_on WIDTH */
               
               reg [PV-1       :   0] full_adaptive_ovc_mask,full_adaptive_ovc_mask_next; 
               
              
        
                always @(*) begin
                    for(k=0;    k<PV; k=k+1'b1) begin
                     //in full adaptive routing, adaptive VCs located in y axies can not be reallocated non-atomicly   
                        if( AVC_ATOMIC_EN== 0) begin 
                            if((((k/V) == NORTH ) || ((k/V) == SOUTH )) && (  ADAPTIVE_VC_MASK[k%V]))  
                                    full_adaptive_ovc_mask_next[k]  =   (credit_counter_next[k]         == Bint);
                            else    full_adaptive_ovc_mask_next[k] = ~nearly_full_all_next[k];
                        end else begin 
                            if(  ADAPTIVE_VC_MASK[k%V])  
                                    full_adaptive_ovc_mask_next[k]  =   (credit_counter_next[k]         == Bint);
                            else    full_adaptive_ovc_mask_next[k] = ~nearly_full_all_next[k];
                        
                        
                        end                       
                        
                     end // for  
                end//always

         always @(posedge clk or posedge reset) begin
                        if(reset) begin 
                            full_adaptive_ovc_mask    <=  {PV{1'b0}};
                        end else begin 
                            full_adaptive_ovc_mask    <= full_adaptive_ovc_mask_next;
                        end                    
                end//always
        

                assign ovc_avalable_all              = ~ovc_status & full_adaptive_ovc_mask;
            
            end else begin :paradapt //par adaptive
                assign ovc_avalable_all             = ~(ovc_status | nearly_full_all);
           end
        end //NONATOMIC 
    endgenerate
    
    
    
    assign credit_increased_all         = credit_in_all;
    
    assign assigned_ovc_not_full_all    =    ~ assigned_ovc_is_full_all;
    
    
    genvar i,j;
    generate
    for(i=0;i<P;i=i+1    ) begin :port_lp
    
        inport_module_can #(
            .V    (V), // vc_num_per_port
            .P    (P) // router port num
        )inport_module
        (
            .flit_is_tail                                (flit_is_tail_all                        [(i+1)*V-1        :i*V]),
            .assigned_ovc_num                            (assigned_ovc_num_all                [(i+1)*VV-1        :i*VV]),
            .spec_ovc_num                                (spec_ovc_num_all                        [(i+1)*VV-1        :i*VV]),
            .nonspec_granted_dest_port                (nonspec_granted_dest_port_all    [(i+1)*P_1-1    :i*P_1]),
            .spec_granted_dest_port                    (spec_granted_dest_port_all        [(i+1)*P_1-1    :i*P_1]),
            .nonspec_first_arbiter_granted_ivc    (nonspec_first_arbiter_granted_ivc_all    [(i+1)*V-1        :i*V]),
            .spec_first_arbiter_granted_ivc        (spec_first_arbiter_granted_ivc_all    [(i+1)*V-1        :i*V]),
            .credit_decreased                            (credit_decreased                        [i]),
            .ovc_released                                (ovc_released                            [i])
        
        );    

    end//for
    
    
    
    for(i=0;i< PV;i=i+1) begin :total_vc_loop2
        for(j=0;j<P;    j=j+1)begin: assign_loop2
            if((i/V)<j )begin: jj
                assign ovc_released_gen        [i][j-1]    = ovc_released[j][i];
                assign credit_decreased_gen[i][j-1]    = credit_decreased [j][i];
            end else if((i/V)>j) begin: hh
                assign ovc_released_gen        [i][j]    = ovc_released[j][i-V];
                assign credit_decreased_gen[i][j]    = credit_decreased[j][i-V];
            end
        end//j
        assign non_ss_ovc_released_all     [i] = |ovc_released_gen[i];
        assign non_ss_credit_decreased_all [i] = (|credit_decreased_gen[i])|non_ss_ovc_allocated_all[i];
    end//i
    
    

    
    
    //remove source port from the list 
    for(i=0;i< P;i=i+1) begin :port_loop
        if(i==0)        begin :i0
            assign credit_in_perport    [i]=credit_in_all     [PV-1                :    V];
            assign full_perport             [i]=full_all              [PV-1                :    V];
            assign nearly_full_perport    [i]=nearly_full_all    [PV-1                :    V];
        end else if(i==(P-1)) begin  :ip_1
            assign credit_in_perport    [i]=credit_in_all     [PV-V-1            :    0];
            assign full_perport             [i]=full_all              [PV-V-1            :    0];
            assign nearly_full_perport    [i]=nearly_full_all    [PV-V-1            :    0];
        end else begin : els
            assign credit_in_perport    [i]={credit_in_all     [PV-1    :    (i+1)*V],credit_in_all     [(i*V)-1    :    0]};
            assign full_perport             [i]={full_all          [PV-1    :    (i+1)*V],full_all         [(i*V)-1    :    0]};
            assign nearly_full_perport    [i]={nearly_full_all [PV-1    :    (i+1)*V],nearly_full_all[(i*V)-1    :    0]};
        end
    end//for
    
    
    
    for(i=0;i< PV;i=i+1) begin :PV_loop2
        sw_mask_gen_can #(
            .V (V), // vc_num_per_port
            .P    (P) // router port num
        )sw_mask
        (
            .assigned_ovc_num            (assigned_ovc_num_all[(i+1)*V-1        :i*V]),
            .dest_port                    (dest_port_all            [(i+1)*P_1-1    :i*P_1]),
            .full                        (full_perport            [i/V]),
            .credit_increased            (credit_in_perport    [i/V]),
            .nearly_full                (nearly_full_perport    [i/V]),
            .ivc_getting_sw_grant    (ivc_num_getting_sw_grant[i]),
            .assigned_ovc_is_full    (assigned_ovc_is_full_all[i]),
            .clk                            (clk),
            .reset                        (reset)
        );
    end//for
    
    for(i=0;    i<PV; i=i+1) begin :register_loop
        always @(posedge clk or posedge reset) begin
            if(reset) begin 
                credit_counter[i]    <=    Bint;
                ovc_status[i]        <=    1'b0;
                full_all[i]            <=    1'b0;
                nearly_full_all[i]<=    1'b0;
            end else begin 
                credit_counter[i]    <=    credit_counter_next[i];
                full_all[i]            <=    full_all_next[i];
                nearly_full_all[i]<=    nearly_full_all_next[i];
                if(ovc_released_all[i] )        ovc_status[i]<=1'b0;
                if(ovc_allocated_all[i])    ovc_status[i]<=1'b1;
            end
        end//always
    end//for

        
    
    endgenerate
    
 port_pre_sel_gen #(
        .P(P),
        .V(V),
        .B(B),
        .CONGESTION_INDEX(CONGESTION_INDEX),
        .CONGw(CONGw),
        .ROUTE_TYPE(ROUTE_TYPE),
        .ESCAP_VC_MASK(ESCAP_VC_MASK)

    )
     port_pre_sel_top    
    (
        .port_pre_sel(port_pre_sel),
        .ovc_status(ovc_status),
        .ovc_avalable_all(ovc_avalable_all),
        .credit_decreased_all(credit_decreased_all),
        .credit_increased_all(credit_increased_all),
        .congestion_in_all(congestion_in_all),
        .reset(reset),
        .clk(clk)

    );    
    
    
    
    always @(*) begin
        for(k=0;    k<PV; k=k+1) begin 
            credit_counter_next[k]    =    credit_counter[k];
            if(credit_increased_all[k]    & ~credit_decreased_all[k]) begin 
                credit_counter_next[k]    = credit_counter[k]+1'b1;
            end else if (~credit_increased_all[k]    & credit_decreased_all[k])begin    
                credit_counter_next[k]    = credit_counter[k]-1'b1;
            end
        end
    end
    
    always @(*) begin
        for(k=0;    k<PV; k=k+1) begin 
            full_all_next[k]            =     credit_counter_next[k]         == {Bw{1'b0}};
            nearly_full_all_next[k]    =    credit_counter_next[k]         <= 1;
        end    
    end
    
    
    
    //synthesis translate_off 
    //synopsys  translate_off
generate 
if(DEBUG_EN) begin :dbg
    always @(posedge clk) begin
       if(!reset)begin 
        for(k=0;    k<PV; k=k+1'b1) begin 
            if(credit_counter[k]== Bint && credit_increased_all[k])
                $display("%t: ERROR: unexpected credit is received for an empty ovc: %m",$time);
            if(credit_counter[k]== {Bw{1'b0}} && credit_decreased_all[k])
                $display("%t: ERROR: Attempt to send flit to a full ovc: %m",$time);
            if(ovc_released_all[k] && ovc_allocated_all[k])        
                $display("%t: ERROR: simultaneous allocation and release for an OVC: %m",$time);
            if(ovc_released_all[k] && ovc_status[k]==1'b0)
                $display("%t: ERROR: Attempt to release an unallocated OVC: %m",$time);
            if(ovc_allocated_all[k] && ovc_status[k]==1'b1)
                $display("%t: ERROR: Attempt to allocate an allocated OVC: %m",$time);
        end//for
       end
    end
    /*
    localparam NUM_WIDTH = log2(PV+1);
    wire [NUM_WIDTH-1        :    0] num1,num2;
    set_bits_counter #(
        .IN_WIDTH(PV)
    )cnt1
    (
        .in        (ovc_status),
        .out        (num1)
    );

    set_bits_counter #(
        .IN_WIDTH(PV)
    )cnt2
    (
        .in        (ovc_is_assigned_all),
        .out        (num2)
    );
    
    always @(posedge clk) begin
        if(num1    != num2 ) $display("%t: ERROR: number of assigned IVC mismatch the number of occupied OVC: %m",$time);
    end
    */
end
endgenerate    
    //synopsys  translate_on
    //synthesis translate_on
    
    
    
    
endmodule 

/************************************

        inport_module
        

*************************************/
module inport_module_can #(
    parameter V = 4, // vc_num_per_port
    parameter P    = 5 // router port num
)(
    flit_is_tail,
    assigned_ovc_num,
    spec_ovc_num,
    nonspec_granted_dest_port,
    spec_granted_dest_port,
    nonspec_first_arbiter_granted_ivc,
    spec_first_arbiter_granted_ivc,
    credit_decreased,
    ovc_released
    
);    
    
    localparam      VV        =    V        *    V,
                    P_1    =    P-1    ,
                    VP_1    =    V        *     P_1;            
                    
                    
                    
    input    [V-1        :    0]    flit_is_tail;
    input    [VV-1        :    0]    assigned_ovc_num;
    input    [VV-1        :    0] spec_ovc_num;
    input    [P_1-1    :    0]    nonspec_granted_dest_port;
    input    [P_1-1    :    0]    spec_granted_dest_port;
    input    [V-1        :    0]    nonspec_first_arbiter_granted_ivc;
    input    [V-1        :    0] spec_first_arbiter_granted_ivc;
    output[VP_1-1    :    0]    credit_decreased;
    output[VP_1-1    :    0]    ovc_released;
    
    
    
    wire [V-1        :    0] nonspec_muxout1,spec_muxout1;
    wire                        muxout2;
    wire [VP_1-1    :    0]    nonspec_credit_decreased,spec_credit_decreased;
    // assigned ovc mux 
    one_hot_mux #(
        .IN_WIDTH    (VV),
        .SEL_WIDTH  (V)
    )assigned_ovc_mux
    (
        .mux_in        (assigned_ovc_num),
        .mux_out        (nonspec_muxout1),
        .sel            (nonspec_first_arbiter_granted_ivc)
    );
    
    
    one_hot_mux #(
        .IN_WIDTH    (VV),
        .SEL_WIDTH  (V)
    )spec_ovc_mux
    (
        .mux_in        (spec_ovc_num),
        .mux_out        (spec_muxout1),
        .sel            (spec_first_arbiter_granted_ivc)
    );
    // tail mux 
    one_hot_mux #(
        .IN_WIDTH    (V),
        .SEL_WIDTH  (V)
    )tail_mux
    (
        .mux_in        (flit_is_tail),
        .mux_out        (muxout2),
        .sel            (nonspec_first_arbiter_granted_ivc)
    );
    
    
    one_hot_demux    #(
        .IN_WIDTH    (V),
        .SEL_WIDTH    (P_1)
        
    ) nonspecdemux
    (
        .demux_sel    (nonspec_granted_dest_port),//selectore
        .demux_in    (nonspec_muxout1),//repeated
        .demux_out    (nonspec_credit_decreased)
    );
    
    one_hot_demux    #(
        .IN_WIDTH    (V),
        .SEL_WIDTH    (P_1)
        
    ) specdemux
    (
        .demux_sel    (spec_granted_dest_port),//selectore
        .demux_in    (spec_muxout1),//repeated
        .demux_out    (spec_credit_decreased)
    );
    
    assign ovc_released         = (muxout2)? nonspec_credit_decreased : {VP_1{1'b0}};
    assign credit_decreased    =    nonspec_credit_decreased | spec_credit_decreased;
    
endmodule


/**********************************

    sw_mask_gen

*********************************/

module sw_mask_gen_can #(
        parameter V = 4, // vc_num_per_port
        parameter P    = 5 // router port num
)(
    assigned_ovc_num,
    dest_port,
    full,
    credit_increased,
    nearly_full,
    ivc_getting_sw_grant,
    assigned_ovc_is_full,
    clk,reset
);
    localparam  P_1    =    P-1    ,
                VP_1    =    V        *     P_1;                
            
                    
    input    [V-1            :    0]    assigned_ovc_num;
    input    [P_1-1        :    0]    dest_port;
    input    [VP_1-1        :    0]    full;
    input    [VP_1-1        :    0]    credit_increased;
    input    [VP_1-1        :    0]    nearly_full;
    input                            ivc_getting_sw_grant;
    output                        assigned_ovc_is_full;
    input                         clk,reset;


    wire        [VP_1-1        :    0]    full_muxin1,nearly_full_muxin1;
    wire         [V-1            :    0]    full_muxout1,nearly_full_muxout1;
    wire                                full_muxout2,nearly_full_muxout2;
    reg    full_reg1,full_reg1_next;
    reg    full_reg2,full_reg2_next;
    
    
    assign full_muxin1             = full & (~credit_increased);
    assign nearly_full_muxin1     = nearly_full & (~credit_increased);
    
    
    // destport mux 
    one_hot_mux #(
        .IN_WIDTH    (VP_1),
        .SEL_WIDTH  (P_1)
    )full_mux1
    (
        .mux_in        (full_muxin1),
        .mux_out        (full_muxout1),
        .sel            (dest_port)
    );
    
    one_hot_mux #(
        .IN_WIDTH    (VP_1),
        .SEL_WIDTH  (P_1)
    )nearly_full_mux1
    (
        .mux_in        (nearly_full_muxin1),
        .mux_out        (nearly_full_muxout1),
        .sel            (dest_port)
    );
    
    // assigned ovc mux 
    one_hot_mux #(
        .IN_WIDTH    (V),
        .SEL_WIDTH  (V)
    )full_mux2
    (
        .mux_in        (full_muxout1),
        .mux_out        (full_muxout2),
        .sel            (assigned_ovc_num)
    );
    
    
    one_hot_mux #(
        .IN_WIDTH    (V),
        .SEL_WIDTH  (V)
    )nearlfull_mux2
    (
        .mux_in        (nearly_full_muxout1),
        .mux_out        (nearly_full_muxout2),
        .sel            (assigned_ovc_num)
    );
    
    always @(*) begin 
        full_reg1_next    =    full_muxout2;
        full_reg2_next    =    nearly_full_muxout2 & ivc_getting_sw_grant;
    end
    
    always @(posedge clk or posedge reset) begin 
        if(reset)  begin     
            full_reg1    <= 1'b0;
            full_reg2    <= 1'b0;
        end else begin 
            full_reg1    <= full_reg1_next;
            full_reg2    <= full_reg2_next;
        end
    end//always
    
    assign assigned_ovc_is_full    = full_reg1 | full_reg2;
    
endmodule
