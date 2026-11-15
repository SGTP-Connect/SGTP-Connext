import {test} from 'node:test';import assert from 'node:assert/strict';import {totals} from '../budget/model.js';
test('forecast counts approved unpaid costs, not just cash paid',()=>{const t=totals(10000,Array.from({length:10},()=>({type:'league',cost:300,paid:200})));assert.equal(t.remaining,7000);assert.equal(t.owed,1000);assert.equal(t.forecast,1000);assert.equal(t.allowance,350)});
test('cup games do not change spend or league forecast',()=>{assert.deepEqual(totals(10000,[{type:'cup',cost:100,paid:100}]),totals(10000,[]))});
test('overspend and completed season',()=>{const t=totals(10000,Array.from({length:30},()=>({type:'league',cost:400,paid:0})));assert.equal(t.remaining,-2000);assert.equal(t.forecast,-2000);assert.equal(t.allowance,null)});
