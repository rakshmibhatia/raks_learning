// Copyright 2019, Intel Corporation

include "pmlc/util/enums.td"
include "pmlc/dialect/eltwise/predicates.td"

def StripeDialect : Dialect {
  let name = "stripe";
  let cppNamespace = "pmlc::dialect::stripe";
}

def AffineType : Type<CPred<"$_self.isa<AffineType>()">, "Plaid Affine Type">;
def TensorType : Type<CPred<"$_self.isa<TensorType>()">, "Plaid Tensor Type">;
def TensorRefType : Type<CPred<"$_self.isa<TensorRefType>()">, "Plaid Tensor Reference Type">;
def TensorTypeAttr : TypeAttrBase<"TensorType", "tensor type attribute">;

class StripeOp<string mnemonic, list<OpTrait> traits = []> :
    Op<StripeDialect, mnemonic, traits>;

def AllocateOp : StripeOp<"alloc"> {
  let summary = "Allocate a new tensor and set its intial shape / size";
  let arguments = (ins TensorTypeAttr:$layout);
  let results = (outs TensorRefType:$result);

  let builders = [OpBuilder<
    "Builder* builder, OperationState& result, TensorType type", [{
      result.addAttribute("layout", builder->getTypeAttr(type));
      result.addTypes(TensorRefType::get(type));
    }]
  >];
  let printer = [{ PrintSimple(getOperation(), &p, 0, {}, Type(), false); }];
  let parser = [{
    llvm::SmallVector<OpAsmParser::OperandType, 0> operands;
    bool r = ParseSimple(&parser, &result, &operands, 0, {}, static_cast<Type*>(nullptr), false);
    for (auto& kvp : result.attributes) {
      if (kvp.first.str() != "layout") continue;
      TypeAttr ta = kvp.second.dyn_cast<TypeAttr>();
      if (!ta) continue;
      auto layout = ta.getValue().dyn_cast<TensorType>();
      if (!layout) continue;
      result.addTypes(TensorRefType::get(layout.getElementType(), layout.getRank(), layout.is_const()));
    }
    return mlir::failure(r); 
  }];
}

def RefineOp : StripeOp<"refine", [NoSideEffect]> {
  let summary = "Modify the offset into a tensor in an affine way";
  let arguments = (ins TensorRefType:$in, Variadic<AffineType>:$offsets);
  let results = (outs TensorRefType:$result);

  let printer = [{ PrintSimple(getOperation(), &p, 1, {}, in()->getType(), true); }];
  let parser = [{
    TensorRefType refType;
    auto aff_type = AffineType::get(parser.getBuilder().getContext());
    llvm::SmallVector<OpAsmParser::OperandType, 8> operands;
    bool r = ParseSimple(&parser, &result, &operands, 1, {}, &refType, true);
    r = r || parser.resolveOperand(operands[0], refType, result.operands);
    for (size_t i = 1; i < operands.size(); i++) {
      r = r || parser.resolveOperand(operands[i], aff_type, result.operands);
    }
    r = r || parser.addTypeToList(refType, result.types);
    return mlir::failure(r); 
  }];

  let extraClassDeclaration = [{
    Value* getOffset(unsigned i) {
      // skip the $in operand
      return getOperand(i + 1);
    }
  }];
}

def LoadOp : StripeOp<"load"> {
  let summary = "Load from a tensor";
  let arguments = (ins TensorRefType:$from);
  let results = (outs Eltwise_AnyTensor:$into);
  let printer = [{ PrintSimple(getOperation(), &p, 1, {}, from()->getType(), false); }];
  let parser = [{
    TensorRefType refType;
    llvm::SmallVector<OpAsmParser::OperandType, 1> operands;
    bool r = ParseSimple(&parser, &result, &operands, 1, {}, &refType, false);
    Type eltType = RankedTensorType::get({}, refType.getElementType());
    r = r || parser.resolveOperand(operands[0], refType, result.operands);
    r = r || parser.addTypeToList(eltType, result.types);
    return mlir::failure(r); 
  }];
}

def LoadIndexOp : StripeOp<"load_index"> {
  let summary = "Convert an affine expression into a scalar value";
  let arguments = (ins AffineType:$from);
  let results = (outs Eltwise_AnyTensor:$into);
}

def StoreOp : StripeOp<"store"> {
  let summary = "Store into a tensor";
  let arguments = (ins TensorRefType:$into, Eltwise_AnyTensor:$from);
  let printer = [{ PrintSimple(getOperation(), &p, 2, {}, into()->getType(), false); }];
  let parser = [{
    TensorRefType refType;
    llvm::SmallVector<OpAsmParser::OperandType, 2> operands;
    bool r = ParseSimple(&parser, &result, &operands, 2, {}, &refType, false);
    Type eltType = RankedTensorType::get({}, refType.getElementType());
    r = r || parser.resolveOperand(operands[0], refType, result.operands);
    r = r || parser.resolveOperand(operands[1], eltType, result.operands);
    return mlir::failure(r); 
  }];
}

def AggregateOp : StripeOp<"aggregate"> {
  let summary = "A accumulating store with a commutative, associative accumulation";
  let arguments = (ins TensorRefType:$into, Eltwise_AnyTensor:$from, AggregationKind:$agg);
  let results = (outs);
  let printer = [{ PrintSimple(getOperation(), &p, 2, {}, into()->getType(), false); }];
  let parser = [{
    TensorRefType refType;
    llvm::SmallVector<OpAsmParser::OperandType, 2> operands;
    bool r = ParseSimple(&parser, &result, &operands, 2, {}, &refType, false);
    Type eltType = RankedTensorType::get({}, refType.getElementType());
    r = r || parser.resolveOperand(operands[0], refType, result.operands);
    r = r || parser.resolveOperand(operands[1], eltType, result.operands);
    return mlir::failure(r); 
  }];
}

class AffineOp<string mnemonic> : StripeOp<mnemonic, [NoSideEffect]> {
  let results = (outs AffineType:$result);
}

def AffineConstOp : AffineOp<"affine_const"> {
  let summary = "A constant affine value";
  let arguments = (ins I64Attr:$value);
  let printer = [{ PrintSimple(getOperation(), &p, 0, {"value"}, Type(), false); }];
  let parser = [{
    auto aff_type = AffineType::get(parser.getBuilder().getContext());
    llvm::SmallVector<OpAsmParser::OperandType, 0> operands;
    bool r = ParseSimple(&parser, &result, &operands, 0, {"value"}, static_cast<Type*>(nullptr), false);
    r = r || parser.addTypeToList(aff_type, result.types);
    return mlir::failure(r); 
  }];
}

def AffineMulOp : AffineOp<"affine_mul"> {
  let summary = "Multiply an affine by a constant value";
  let arguments = (ins AffineType:$input, I64Attr:$scale);
  let printer = [{ PrintSimple(getOperation(), &p, 1, {"scale"}, Type(), false); }];
  let parser = [{
    auto aff_type = AffineType::get(parser.getBuilder().getContext());
    llvm::SmallVector<OpAsmParser::OperandType, 1> operands;
    bool r = ParseSimple(&parser, &result, &operands, 1, {"scale"}, static_cast<Type*>(nullptr), false);
    r = r || parser.resolveOperand(operands[0], aff_type, result.operands);
    r = r || parser.addTypeToList(aff_type, result.types);
    return mlir::failure(r); 
  }];
}

def AffineAddOp : AffineOp<"affine_add"> {
  let summary = "Add multiple affines together";
  let arguments = (ins Variadic<AffineType>:$inputs); 
  let printer = [{ PrintSimple(getOperation(), &p, 0, {}, Type(), true); }];
  let parser = [{
    auto aff_type = AffineType::get(parser.getBuilder().getContext());
    llvm::SmallVector<OpAsmParser::OperandType, 4> operands;
    bool r = ParseSimple(&parser, &result, &operands, 0, {}, static_cast<Type*>(nullptr), true);
    r = r || parser.resolveOperands(operands, aff_type, result.operands);
    r = r || parser.addTypeToList(aff_type, result.types);
    return mlir::failure(r); 
  }];
}

def ParallelForOp : StripeOp<"parallel_for"> {
  let summary = "Parallel for loop";
  // At some point, we should be able to dynamically control ranges
  // Variadic<IntegerType>:$dyn_ranges
  let arguments = (ins I64ArrayAttr:$ranges);
  let regions = (region SizedRegion<1>:$inner);
  let printer = [{
    p << getOperation()->getName() << " (";
    llvm::SmallVector<StringRef, 8> skip;
    skip.push_back("ranges");
    skip.push_back("idx_names");
    auto names = getAttrOfType<ArrayAttr>(mlir::Identifier::get("idx_names", getContext())); 
    for(size_t i = 0; i < ranges().size(); i++) {
      auto idx_name = StringAttr::get("", getContext());
      if (names && names.size() > i) {
        if (auto str_attr = names.getValue()[i].template dyn_cast<StringAttr>()) {
          idx_name = str_attr;
        }
      }
      p << idx_name << ":" << ranges().getValue()[i].cast<IntegerAttr>().getInt();
      if (i + 1 != ranges().size()) {
        p << ", ";
      }
    }
    p << ")";
    p.printNewline(1);
    p.printOptionalAttrDict(getOperation()->getAttrs(), skip);
    p.printRegion(inner());
  }];
  let parser = [{
    bool r = false;
    r = r || parser.parseLParen();
    //size_t i = 0;
    MLIRContext* ctx = parser.getBuilder().getContext();
    std::vector<std::string> idx_name;
    std::vector<int64_t> idx_range;
    llvm::SmallVector<mlir::Attribute, 8> ranges;
    llvm::SmallVector<mlir::Attribute, 8> idx_names;
    while (!r) {
      if (!parser.parseOptionalRParen()) {
        break;
      }
      parser.parseOptionalComma();
      StringAttr idx_name;
      IntegerAttr idx_range;
      llvm::SmallVector<NamedAttribute, 2> ignore;
      r = r || parser.parseAttribute(idx_name, mlir::NoneType::get(ctx), "name", ignore);
      r = r || parser.parseColon();
      r = r || parser.parseAttribute(idx_range, Type(), "range", ignore);
      if (!r) {
        idx_names.push_back(idx_name);
        ranges.push_back(idx_range);
      }  
    }
    r = r || parser.parseOptionalAttributeDict(result.attributes);
    auto ranges_attr = ArrayAttr::get(ranges, ctx);
    auto idx_names_attr = ArrayAttr::get(idx_names, ctx);
    result.attributes.emplace_back(mlir::Identifier::get("ranges", ctx), ranges_attr);
    result.attributes.emplace_back(mlir::Identifier::get("idx_names", ctx), idx_names_attr);
    result.regions.emplace_back(new Region(nullptr));
    r = r || parser.parseRegion(*result.regions.back(), {}, {}, false);
    return mlir::failure(r);
  }];
}

def ConstraintOp : StripeOp<"constraint"> {
  let arguments = (ins AffineType:$input);
  let regions = (region AnyRegion:$ge_case, AnyRegion:$lt_case);
  let printer = [{
    p << getOperation()->getName() << " ";
    p.printOperand(input());
    p.printRegion(ge_case());
    if (!lt_case().empty()) {
      p.printRegion(lt_case());
    }
  }];
  let parser = [{
    auto aff_type = AffineType::get(parser.getBuilder().getContext());
    OpAsmParser::OperandType op;
    bool r = false;
    r = r || parser.parseOperand(op);
    r = r || parser.resolveOperand(op, aff_type, result.operands);
    result.regions.emplace_back(new Region(nullptr));
    r = r || parser.parseRegion(*result.regions.back(), {}, {});
    result.regions.emplace_back(new Region(nullptr));
    r = r || parser.parseOptionalRegion(*result.regions.back(), {}, {});
    return mlir::failure(r);
  }];
}

def SpecialOpInterface : OpInterface<"SpecialOp"> {
  let methods = [
    InterfaceMethod<"TODO", "size_t", "getNumInputs">,
    InterfaceMethod<"TODO", "size_t", "getNumOutputs">,
  ];
}

class SpecialOp<string mnemonic, int num_out, int num_in> :
    StripeOp<mnemonic, [SpecialOpInterface]> {
  let results = (outs);
  let extraClassDeclaration = [{
    size_t getNumOutputs() { return }] # num_out # [{;}
    size_t getNumInputs() { return }] # num_in # [{;}
  }];
}

def ReshapeOp : SpecialOp<"reshape", 1, 1> {
  let arguments = (ins
    TensorRefType:$into,
    TensorRefType:$from
  );
}

def ShapeOp : SpecialOp<"shape", 1, 1> {
  let arguments = (ins
    TensorRefType:$shape,
    TensorRefType:$tensor
  );
}

def GatherOp : SpecialOp<"gather", 1, 2> {
  let arguments = (ins
    TensorRefType:$out,
    TensorRefType:$idxs,
    TensorRefType:$table
  );
}

def ScatterOp : SpecialOp<"scatter", 1, 3> {
  let arguments = (ins
    TensorRefType:$out,
    TensorRefType:$expr,
    TensorRefType:$idxs,
    TensorRefType:$val
  );
}

def PrngStepOp : SpecialOp<"prng_step", 2, 1> {
  let arguments = (ins
    TensorRefType:$state_out, 
    TensorRefType:$buffer_out,
    TensorRefType:$state_in
  );
}

def TerminateOp : StripeOp<"terminate", [Terminator]> {
  let summary = "A block terminator since MLIR requires one";
  let parser = [{ return mlir::success(); }];
  let printer = [{ p << getOperationName(); }];
}

def ExecuteOnOp : StripeOp<"execute_on", [Terminator, HasParent<"ParallelForOp">]> {
  let summary = "Indicates where a ParallelForOp should execute";

  // 'from' represents the executor value being returned.
  let arguments = (ins TensorRefType:$from);
  let printer = [{ PrintSimple(getOperation(), &p, 1, {}, from()->getType(), false); }];
  let parser = [{
    TensorRefType refType;
    llvm::SmallVector<OpAsmParser::OperandType, 1> operands;
    bool r = ParseSimple(&parser, &result, &operands, 1, {}, &refType, false);
    r = r || parser.resolveOperand(operands[0], refType, result.operands);
    return mlir::failure(r); 
  }];
}