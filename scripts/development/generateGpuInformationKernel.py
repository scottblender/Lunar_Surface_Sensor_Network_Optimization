"""Generate scalar-only CUDA-arrayfun kernel; no external CUDA compiler needed.

MATLAB GPU arrayfun disallows local matrix allocation and indexed writes. Unroll
6x6 products into scalar registers, leaving epochs/sensors as runtime loops.
Regenerate the kernel between its markers in createBatchedInformationObjective.m.
"""
from pathlib import Path


def generate():
    lines = []
    def emit(s): lines.append('        ' + s)
    def p(i,j): return f'p{min(i,j)}{max(i,j)}'
    def dot(xs): return ' + '.join(xs)
    emit('function score = trajectory(n1,n2,n3,object)')
    emit('% One CUDA thread per network/object; double scalar registers only.')
    for i in range(1,7):
        for j in range(i,7): emit(f'{p(i,j)} = 0.5*(prior({i},{j},object)+prior({j},{i},object));')
    emit('score = 0;')
    emit('for epoch = 1:nt')
    for i in range(1,7):
        for j in range(1,7): emit(f'f{i}{j} = transitions({i},{j},epoch,object);')
    for i in range(1,7):
        for j in range(1,7): emit(f't{i}{j} = '+dot([f'f{i}{k}*{p(k,j)}' for k in range(1,7)])+';')
    for i in range(1,7):
        for j in range(i,7):
            a=dot([f't{i}{k}*f{j}{k}' for k in range(1,7)])
            b=dot([f't{j}{k}*f{i}{k}' for k in range(1,7)])
            emit(f'{p(i,j)} = 0.5*({a} + {b} + noise({i},{j},epoch,object)+noise({j},{i},epoch,object));')
    emit('for sensor = 1:3')
    emit('if sensor==1, site=n1; elseif sensor==2, site=n2; else, site=n3; end')
    emit('x = reference(1,epoch,object)-(xyz(site,1)*cosine(epoch)-xyz(site,2)*sine(epoch));')
    emit('y = reference(2,epoch,object)-(xyz(site,1)*sine(epoch)+xyz(site,2)*cosine(epoch));')
    emit('z = reference(3,epoch,object)-xyz(site,3);')
    emit('rho2=x*x+y*y; range2=rho2+z*z;')
    emit('if ~(rho2>0 && range2>0), score=NaN; return; end')
    emit('if availability(site,epoch,object)')
    emit('rho=sqrt(rho2);')
    emit('h11=-y/rho2; h12=x/rho2; h13=0;')
    emit('h21=-x*z/(range2*rho); h22=-y*z/(range2*rho); h23=rho/range2;')
    emit('rindex=1; if perSiteNoise, rindex=site; end')
    emit('r11=measurement(1,1,rindex); r12=measurement(1,2,rindex); r22=measurement(2,2,rindex);')
    for i in range(1,7):
        for j in range(1,3): emit(f'b{i}{j} = '+dot([f'{p(i,k)}*h{j}{k}' for k in range(1,4)])+';')
    emit('s11=h11*b11+h12*b21+h13*b31+r11;')
    emit('s12=h11*b12+h12*b22+h13*b32+r12;')
    emit('s21=h21*b11+h22*b21+h23*b31+r12;')
    emit('s22=h21*b12+h22*b22+h23*b32+r22;')
    # Cholesky of the 2x2 symmetric innovation, avoiding determinant cancellation.
    emit('if ~(s11>0), score=NaN; return; end')
    emit('s12=0.5*(s12+s21); c11=sqrt(s11); c21=s12/c11; pivot=s22-c21*c21;')
    emit('if ~(pivot>0), score=NaN; return; end')
    emit('c22=sqrt(pivot);')
    for i in range(1,7):
        emit(f'y1=b{i}1/c11; y2=(b{i}2-c21*y1)/c22;')
        emit(f'k{i}2=y2/c22; k{i}1=(y1-c21*k{i}2)/c11;')
    for i in range(1,7):
        for j in range(1,7):
            expr=f'{int(i==j)}'
            if j<=3: expr+=f'-k{i}1*h1{j}-k{i}2*h2{j}'
            emit(f'a{i}{j} = {expr};')
    for i in range(1,7):
        for j in range(1,7): emit(f'b{i}{j} = '+dot([f'a{i}{k}*{p(k,j)}' for k in range(1,7)])+';')
    for i in range(1,7):
        for j in range(i,7):
            a=dot([f'b{i}{k}*a{j}{k}' for k in range(1,7)])
            b=dot([f'b{j}{k}*a{i}{k}' for k in range(1,7)])
            emit(f'u{i}{j} = 0.5*({a} + {b}) + k{i}1*r11*k{j}1 + k{i}1*r12*k{j}2 + k{i}2*r12*k{j}1 + k{i}2*r22*k{j}2;')
    for i in range(1,7):
        for j in range(i,7): emit(f'{p(i,j)} = u{i}{j};')
    emit('end')
    emit('end')
    emit('% Cholesky of normalized covariance: same logdet metric as CPU.')
    for j in range(1,7):
        sub=''.join(f'-l{j}{k}*l{j}{k}' for k in range(1,j))
        emit(f'pivot={p(j,j)}/(scales({j})*scales({j})){sub};')
        emit('if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end')
        emit(f'l{j}{j}=sqrt(pivot); score=score-2*log(l{j}{j});')
        for i in range(j+1,7):
            sub=''.join(f'-l{i}{k}*l{j}{k}' for k in range(1,j))
            emit(f'l{i}{j}=({p(i,j)}/(scales({i})*scales({j})){sub})/l{j}{j};')
    emit('end')
    emit('score=score/nt;')
    emit('end')
    return '\n'.join(lines)

if __name__ == '__main__':
    path=Path(__file__).resolve().parents[1]/'optimization/createBatchedInformationObjective.m'
    text=path.read_text()
    start='% BEGIN GENERATED KERNEL'
    end='% END GENERATED KERNEL'
    a,b=text.split(start,1); _,c=b.split(end,1)
    path.write_text(a+start+'\n'+generate()+'\n'+end+c)
