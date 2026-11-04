// {Y,U,V} signed 11-bit gradients; joint tensor magnitude and direction.
// Six registers latency, one pixel/clock. Small synchronous ROMs trade RAM
// for logic; both normalization/quantization steps have an integer test model.
module color_gradient_tensor_pixel (
    input wire clk,rst_n,i_valid,
    input wire [32:0] i_gx,i_gy,
    output wire o_valid,
    output wire [10:0] o_magnitude,
    output wire signed [11:0] o_gx,o_gy
);
    reg [21:0] xx [0:2],yy [0:2];
    reg signed [21:0] xy [0:2];
    reg valid1,valid2;
    reg [21:0] jxx,jyy;
    reg signed [22:0] jxy;
    genvar feature;
    generate for(feature=0;feature<3;feature=feature+1) begin: product
        wire signed [10:0] gx=$signed(i_gx[feature*11 +: 11]);
        wire signed [10:0] gy=$signed(i_gy[feature*11 +: 11]);
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin xx[feature]<=0;yy[feature]<=0;xy[feature]<=0;end
            else begin xx[feature]<=gx*gx;yy[feature]<=gy*gy;xy[feature]<=gx*gy;end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin valid1<=0;valid2<=0;jxx<=0;jyy<=0;jxy<=0;end
        else begin
            valid1<=i_valid;valid2<=valid1;
            jxx<=xx[0]+xx[1]+xx[2];jyy<=yy[0]+yy[1]+yy[2];
            jxy<=$signed({xy[0][21],xy[0]})+$signed({xy[1][21],xy[1]})+$signed({xy[2][21],xy[2]});
        end
    end
    wire signed [22:0] delta=$signed({1'b0,jxx})-$signed({1'b0,jyy});
    wire [23:0] a={1'b0,delta[22] ? (~delta+23'd1):delta};
    wire [23:0] b=jxy[22] ? {~jxy+23'd1,1'b0}:{jxy,1'b0};
    wire [23:0] larger=a>=b ? a:b;
    wire [23:0] smaller=a>=b ? b:a;
    wire [24:0] norm={1'b0,larger}+({1'b0,smaller}>>2)+({1'b0,smaller}>>3);
    wire [23:0] trace={2'b0,jxx}+{2'b0,jyy};
    wire [24:0] capped=norm>{1'b0,trace} ? {1'b0,trace}:norm;
    wire [24:0] twice_lambda={1'b0,trace}+capped;

    function [9:0] direction_address;
        input [23:0] ax,bx;
        reg [23:0] largest,na,nb;
        integer bit_index,shift;
        begin
            // OR has the same leading-one position as max, without compare/mux.
            largest=ax|bx;shift=0;
            for(bit_index=5;bit_index<24;bit_index=bit_index+1)
                if(largest[bit_index]) shift=bit_index-4;
            // Common truncation retains the ratio without two wide adders.
            na=ax>>shift;nb=bx>>shift;
            direction_address={na[4:0],nb[4:0]};
        end
    endfunction
    function [12:0] root_address;
        input [23:0] value;
        reg [2:0] exponent;
        reg [23:0] mantissa;
        integer group;
        begin
            exponent=0;
            for(group=1;group<8;group=group+1)
                if((value>>(8+2*group))!=0) exponent=group;
            mantissa=value>>(2*exponent);
            root_address={exponent,mantissa[9:0]};
        end
    endfunction
    function [9:0] half_angle_minor;
        input integer index;
        begin
            case(index)
                0:half_angle_minor=496;1:half_angle_minor=462;
                2:half_angle_minor=426;3:half_angle_minor=388;
                4:half_angle_minor=349;5:half_angle_minor=310;
                6:half_angle_minor=270;7:half_angle_minor=231;
                8:half_angle_minor=194;9:half_angle_minor=158;
                10:half_angle_minor=126;11:half_angle_minor=97;
                12:half_angle_minor=70;13:half_angle_minor=47;
                14:half_angle_minor=26;default:half_angle_minor=8;
            endcase
        end
    endfunction
    function [10:0] constant_root;
        input integer value;
        integer bit_index,guess,candidate;
        begin
            guess=0;
            for(bit_index=10;bit_index>=0;bit_index=bit_index-1) begin
                candidate=guess|(1<<bit_index);
                if(candidate*candidate<=value) guess=candidate;
            end
            constant_root=guess;
        end
    endfunction
    reg [9:0] direction_rom [0:1023];
    reg [10:0] root_rom [0:1023];
    integer address,pa,pb;
    initial begin
        for(address=0;address<1024;address=address+1) begin
            pa=address>>5;pb=address&31;
            direction_rom[address]=pb==0 ? 0:pa==0 ? 512:half_angle_minor(16*pa/(pa+pb));
            root_rom[address]=constant_root(address<<12); // sqrt(mantissa), Q6.
        end
    end
    reg [23:0] lambda0;
    reg [9:0] dir_address0;
    reg [3:0] flags0,flags1,flags2,flags3; // {valid,y-major,negative Jxy,unused}
    reg [12:0] root_address1;
    reg [2:0] exponent2;
    reg [9:0] minor1,minor2,minor3;
    reg [10:0] root2,magnitude3;
    wire [17:0] scaled_root={7'd0,root2}<<exponent2;
    // ROM read data intentionally has no async reset so it maps to block RAM.
    always @(posedge clk) begin
        minor1<=direction_rom[dir_address0];
        root2<=root_rom[root_address1[9:0]];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            lambda0<=0;dir_address0<=0;flags0<=0;flags1<=0;flags2<=0;flags3<=0;
            root_address1<=0;exponent2<=0;minor2<=0;minor3<=0;magnitude3<=0;
        end else begin
            lambda0<=twice_lambda[24:1];dir_address0<=direction_address(a,b);
            flags0<={valid2,jyy>jxx,jxy[22],1'b0};
            root_address1<=root_address(lambda0);flags1<=flags0;
            exponent2<=root_address1[12:10];minor2<=minor1;flags2<=flags1;
            magnitude3<=scaled_root[17] ? 11'd2047:scaled_root[16:6];
            minor3<=minor2;flags3<=flags2;
        end
    end
    assign o_valid=flags3[3];
    assign o_magnitude=magnitude3;
    wire signed [11:0] dx=flags3[2] ? $signed({2'b0,minor3}):12'sd512;
    wire signed [11:0] dy=flags3[2] ? 12'sd512:$signed({2'b0,minor3});
    assign o_gx=magnitude3==0 ? 12'sd0:dx;
    assign o_gy=magnitude3==0 ? 12'sd0:flags3[1] ? -dy:dy;
endmodule
