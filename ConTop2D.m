function ConTop2D(Macro_struct, Micro_struct, penal, rmin)
%% USER-DEFINED LOOP PARAMETERS
maxloop = 200; E0 = 1; Emin = 1e-9; nu = 0.3;
Macro.length = Macro_struct(1); Macro.width = Macro_struct(2);
Micro.length = Micro_struct(1); Micro.width = Micro_struct(2);
Macro.nelx   = Macro_struct(3); Macro.nely  = Macro_struct(4);
Micro.nelx   = Micro_struct(3); Micro.nely  = Micro_struct(4);
Macro.Vol    = Macro_struct(5); Micro.Vol   = Micro_struct(5);
Macro.Elex = Macro.length/Macro.nelx; Macro.Eley = Macro.width/Macro.nely;
Macro.nele = Macro.nelx*Macro.nely;   Micro.nele = Micro.nelx*Micro.nely;
Macro.ndof = 2*(Macro.nelx+1)*(Macro.nely+1);
% PREPARE FINITE ELEMENT ANALYSIS
[load_x, load_y] = meshgrid(Macro.nelx, Macro.nely/2);
loadnid  = load_x*(Macro.nely+1)+(Macro.nely+1-load_y);
F = sparse(2*loadnid(:), 1, -1, 2*(Macro.nelx+1)*(Macro.nely+1),1);
U = zeros(Macro.ndof,1);
[fixed_x, fixed_y] = meshgrid(0, 0:Macro.nely);
fixednid  = fixed_x*(Macro.nely+1)+(Macro.nely+1-fixed_y);
fixeddofs = [2*fixednid(:); 2*fixednid(:)-1];
freedofs  = setdiff(1:Macro.ndof,fixeddofs);
nodenrs = reshape(1:(Macro.nely+1)*(Macro.nelx+1),1+Macro.nely,1+Macro.nelx);
edofVec = reshape(2*nodenrs(1:end-1,1:end-1)+1,Macro.nele,1);
edofMat = repmat(edofVec,1,8)+repmat([0 1 2*Macro.nely+[2 3 0 1] -2 -1],Macro.nele,1);
iK = reshape(kron(edofMat,ones(8,1))',64*Macro.nele,1);
jK = reshape(kron(edofMat,ones(1,8))',64*Macro.nele,1);
% PREPARE FILTER
[Macro.H,Macro.Hs] = filtering2d(Macro.nelx, Macro.nely, Macro.nele, rmin);
[Micro.H,Micro.Hs] = filtering2d(Micro.nelx, Micro.nely, Micro.nele, rmin);
% INITIALIZE ITERATION
Macro.x = repmat(Macro.Vol,Macro.nely,Macro.nelx);
Micro.x = ones(Micro.nely,Micro.nelx);
for i = 1:Micro.nelx
    for j = 1:Micro.nely
        if sqrt((i-Micro.nelx/2-0.5)^2+(j-Micro.nely/2-0.5)^2) < min(Micro.nelx,Micro.nely)/3
            Micro.x(j,i) = 0;
        end
    end
end
beta = 1;
Macro.xTilde = Macro.x; Micro.xTilde = Micro.x;
Macro.xPhys = 1-exp(-beta*Macro.xTilde)+Macro.xTilde*exp(-beta);
Micro.xPhys = 1-exp(-beta*Micro.xTilde)+Micro.xTilde*exp(-beta);
loopbeta = 0; loop = 0; Macro.change = 1; Micro.change = 1;
while loop < maxloop || Macro.change > 0.01 || Micro.change > 0.01
    loop = loop+1; loopbeta = loopbeta+1;
    % FE-ANALYSIS AT TWO SCALES
    [DH, dDH] = EBHM2D(Micro.xPhys, Micro.length, Micro.width, E0, Emin, nu, penal);
    Ke = elementMatVec2D(Macro.Elex/2, Macro.Eley/2, DH);
    sK = reshape(Ke(:)*(Emin+Macro.xPhys(:)'.^penal*(1-Emin)),64*Macro.nele,1);
    K = sparse(iK,jK,sK); K = (K+K')/2;
    U(freedofs,:) = K(freedofs,freedofs)\F(freedofs,:);
    % OBJECTIVE FUNCTION AND SENSITIVITY ANALYSIS
    ce = reshape(sum((U(edofMat)*Ke).*U(edofMat),2),Macro.nely,Macro.nelx);
    c = sum(sum((Emin+Macro.xPhys.^penal*(1-Emin)).*ce));
    Macro.dc = -penal*(1-Emin)*Macro.xPhys.^(penal-1).*ce;
    Macro.dv = ones(Macro.nely, Macro.nelx);
    Micro.dc = zeros(Micro.nely, Micro.nelx);
    for i = 1:Micro.nele
        dDHe = [dDH{1,1}(i) dDH{1,2}(i) dDH{1,3}(i);
                dDH{2,1}(i) dDH{2,2}(i) dDH{2,3}(i);
                dDH{3,1}(i) dDH{3,2}(i) dDH{3,3}(i)];
        [dKE] = elementMatVec2D(Macro.Elex, Macro.Eley, dDHe);
        dce = reshape(sum((U(edofMat)*dKE).*U(edofMat),2),Macro.nely,Macro.nelx);
        Micro.dc(i) = -sum(sum((Emin+Macro.xPhys.^penal*(1-Emin)).*dce));
    end
    Micro.dv = ones(Micro.nely, Micro.nelx);
    % FILTERING AND MODIFICATION OF SENSITIVITIES
    Macro.dx = beta*exp(-beta*Macro.xTilde)+exp(-beta); Micro.dx = beta*exp(-beta*Micro.xTilde)+exp(-beta);
    Macro.dc(:) = Macro.H*(Macro.dc(:).*Macro.dx(:)./Macro.Hs); Macro.dv(:) = Macro.H*(Macro.dv(:).*Macro.dx(:)./Macro.Hs);
    Micro.dc(:) = Micro.H*(Micro.dc(:).*Micro.dx(:)./Micro.Hs); Micro.dv(:) = Micro.H*(Micro.dv(:).*Micro.dx(:)./Micro.Hs);
    % OPTIMALITY CRITERIA UPDATE MACRO AND MICRO ELELMENT DENSITIES
    [Macro.x, Macro.xPhys, Macro.change] = OC(Macro.x, Macro.dc, Macro.dv, Macro.H, Macro.Hs, Macro.Vol, Macro.nele, 0.2, beta);
    [Micro.x, Micro.xPhys, Micro.change] = OC(Micro.x, Micro.dc, Micro.dv, Micro.H, Micro.Hs, Micro.Vol, Micro.nele, 0.2, beta);
    Macro.xPhys = reshape(Macro.xPhys, Macro.nely, Macro.nelx); Micro.xPhys = reshape(Micro.xPhys, Micro.nely, Micro.nelx);
    % PRINT RESULTS
    fprintf(' It.:%5i Obj.:%11.4f Macro_Vol.:%7.3f Micro_Vol.:%7.3f Macro_ch.:%7.3f Micro_ch.:%7.3f\n',...
        loop,c,mean(Macro.xPhys(:)),mean(Micro.xPhys(:)), Macro.change, Micro.change);
    colormap(gray); imagesc(1-Macro.xPhys); caxis([0 1]); axis equal; axis off; drawnow;
    colormap(gray); imagesc(1-Micro.xPhys); caxis([0 1]); axis equal; axis off; drawnow;
    %% UPDATE HEAVISIDE REGULARIZATION PARAMETER
    if beta < 512 && (loopbeta >= 50 || Macro.change <= 0.01 || Micro.change <= 0.01)
        beta = 2*beta; loopbeta = 0; Macro.change = 1; Micro.change = 1;
        fprintf('Parameter beta increased to %g.\n',beta);
    end
end
end
%% SUB FUNCTION:filtering2D
function [H,Hs] = filtering2d(nelx, nely, nele, rmin)
iH = ones(nele*(2*(ceil(rmin)-1)+1)^2,1);
jH = ones(size(iH));
sH = zeros(size(iH));
k = 0;
for i1 = 1:nelx
    for j1 = 1:nely
        e1 = (i1-1)*nely+j1;
        for i2 = max(i1-(ceil(rmin)-1),1):min(i1+(ceil(rmin)-1),nelx)
            for j2 = max(j1-(ceil(rmin)-1),1):min(j1+(ceil(rmin)-1),nely)
                e2 = (i2-1)*nely+j2;
                k = k+1;
                iH(k) = e1;
                jH(k) = e2;
                sH(k) = max(0,rmin-sqrt((i1-i2)^2+(j1-j2)^2));
            end
        end
    end
end
H = sparse(iH,jH,sH); Hs = sum(H,2);
end
%% SUB FUNCTION: EBHM2D
function [DH, dDH] = EBHM2D(den, lx, ly, E0, Emin, nu, penal)
% the initial definitions of the PUC
D0=E0/(1-nu^2)*[1 nu 0; nu 1 0; 0 0 (1-nu)/2];  % the elastic tensor
[nely, nelx] = size(den);
nele = nelx*nely;
dx = lx/nelx; dy = ly/nely;
Ke = elementMatVec2D(dx/2, dy/2, D0);
Num_node = (1+nely)*(1+nelx);
nodenrs = reshape(1:Num_node,1+nely,1+nelx);
edofVec = reshape(2*nodenrs(1:end-1,1:end-1)+1,nele,1);
edofMat = repmat(edofVec,1,8)+repmat([0 1 2*nely+[2 3 0 1] -2 -1],nele,1);
% 3D periodic boundary formulation
alldofs = (1:2*(nely+1)*(nelx+1));
n1 = [nodenrs(end,[1,end]),nodenrs(1,[end,1])];
d1 = reshape([(2*n1-1);2*n1],1,8);
n3 = [nodenrs(2:end-1,1)',nodenrs(end,2:end-1)];
d3 = reshape([(2*n3-1);2*n3],1,2*(nelx+nely-2));
n4 = [nodenrs(2:end-1,end)',nodenrs(1,2:end-1)];
d4 = reshape([(2*n4-1);2*n4],1,2*(nelx+nely-2));
d2 = setdiff(alldofs,[d1,d3,d4]);
e0 = eye(3);
ufixed = zeros(8,3);
for j = 1:3
    ufixed(3:4,j) = [e0(1,j),e0(3,j)/2;e0(3,j)/2,e0(2,j)]*[lx;0];
    ufixed(7:8,j) = [e0(1,j),e0(3,j)/2;e0(3,j)/2,e0(2,j)]*[0;ly];
    ufixed(5:6,j) = ufixed(3:4,j)+ufixed(7:8,j);
end
wfixed = [repmat(ufixed(3:4,:),nely-1,1);repmat(ufixed(7:8,:),nelx-1,1)];
% the reduced elastic equilibrium equation to compute the induced displacement field
iK = reshape(kron(edofMat,ones(8,1))',64*nelx*nely,1);
jK = reshape(kron(edofMat,ones(1,8))',64*nelx*nely,1);
sK = reshape(Ke(:)*(Emin+den(:)'.^penal*(1-Emin)),64*nelx*nely,1);
K  = sparse(iK,jK,sK); K = (K + K')/2;
Kr = [K(d2,d2),K(d2,d3)+K(d2,d4);K(d3,d2)+K(d4,d2),K(d3,d3)+K(d4,d3)+K(d3,d4)+K(d4,d4)];
U(d1,:)= ufixed;
U([d2,d3],:) = Kr\(-[K(d2,d1);K(d3,d1)+K(d4,d1)]*ufixed-[K(d2,d4);K(d3,d4)+K(d4,d4)]*wfixed);
U(d4,:) = U(d3,:) + wfixed;
% homogenization to evaluate macroscopic effective properties
DH = zeros(3); qe = cell(3,3); dDH = cell(3,3);
cellVolume = lx*ly;
for i = 1:3
    for j = 1:3
        U1 = U(:,i); U2 = U(:,j);
        qe{i,j} = reshape(sum((U1(edofMat)*Ke).*U2(edofMat),2),nely,nelx)/cellVolume;
        DH(i,j) = sum(sum((Emin+den.^penal*(1-Emin)).*qe{i,j}));
        dDH{i,j} = penal*(1-Emin)*den.^(penal-1).*qe{i,j};
    end
end
disp('--- Homogenized elasticity tensor ---'); disp(DH)
end
%% SUB FUNCTION: elementMatVec2D
function Ke = elementMatVec2D(a, b, DH)
GaussNodes = [-1/sqrt(3); 1/sqrt(3)]; GaussWeigh = [1 1];
L = [1 0 0 0; 0 0 0 1; 0 1 1 0];
Ke = zeros(8,8);
for i = 1:2
    for j = 1:2
        GN_x = GaussNodes(i); GN_y = GaussNodes(j);
        dN_x = 1/4*[-(1-GN_x)  (1-GN_x) (1+GN_x) -(1+GN_x)];
        dN_y = 1/4*[-(1-GN_y) -(1+GN_y) (1+GN_y)  (1-GN_y)];
        J = [dN_x; dN_y]*[ -a  a  a  -a;  -b  -b  b  b]';
        G = [inv(J) zeros(size(J)); zeros(size(J)) inv(J)];
        dN(1,1:2:8) = dN_x; dN(2,1:2:8) = dN_y;
        dN(3,2:2:8) = dN_x; dN(4,2:2:8) = dN_y;
        Be = L*G*dN;
        Ke = Ke + GaussWeigh(i)*GaussWeigh(j)*det(J)*Be'*DH*Be;
    end
end
end
%% SUB FUNCTION: OC
function [x, xPhys, change] = OC(x, dc, dv, H, Hs, volfrac, nele, move, beta)
l1 = 0; l2 = 1e9;
while (l2-l1)/(l1+l2) > 1e-4
    lmid = 0.5*(l2+l1);
    xnew = max(0,max(x-move,min(1,min(x+move,x.*sqrt(-dc./dv/lmid)))));
    xTilde(:) = (H*xnew(:))./Hs; xPhys = 1-exp(-beta*xTilde)+xTilde*exp(-beta);
    if sum(xPhys(:)) > volfrac*nele, l1 = lmid; else, l2 = lmid; end
end
change = max(abs(xnew(:)-x(:))); x = xnew;
end
%======================================================================================================================%
% Function ConTop2D:                                                                                                   %
% A compact and efficient MATLAB code for Concurrent topology optimization of multiscale composite structures          %
% in Matlab.                                                                                                           %
%                                                                                                                      %
% Developed by: Jie Gao, Zhen Luo, Liang Xia and Liang Gao*                                                            %
% Email: gaoliang@mail.hust.edu.cn (GabrielJie_Tian@163.com)                                                           %
%                                                                                                                      %
% Main references:                                                                                                     %
%                                                                                                                      %
% (1) Jie Gao, Zhen Luo, Liang Xia, Liang Gao. Concurrent topology optimization of multiscale composite structures     %
% in Matlab. Accepted in Structural and multidisciplinary optimization.                                                %
%                                                                                                                      %
% (2) Xia L, Breitkopf P. Design of materials using topology optimization and energy-based homogenization approach in  %
% Matlab. % Structural and multidisciplinary optimization, 2015, 52(6): 1229-1241.                                     %
%                                                                                                                      %
% *********************************************   Disclaimer   ******************************************************* %
% The authors reserve all rights for the programs. The programs may be distributed and used for academic and           %
% educational purposes. The authors do not guarantee that the code is free from errors,and they shall not be liable    %
% in any event caused by the use of the program.                                                                       %
%======================================================================================================================%
