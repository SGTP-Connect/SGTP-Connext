export function totals(budget,matches){
 const league=matches.filter(m=>m.type==='league');
 const committed=league.reduce((n,m)=>n+m.cost,0),paid=league.reduce((n,m)=>n+m.paid,0),games=league.length;
 const average=games?committed/games:null,remaining=budget-committed;
 return {committed,paid,owed:committed-paid,games,average,remaining,forecast:games?budget-average*30:null,allowance:games<30?remaining/(30-games):null};
}
